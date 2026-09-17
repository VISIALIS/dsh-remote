import Foundation
import Network

/// L'ÉTAT DU CHEMIN RÉSEAU, OBSERVÉ EN CONTINU.
///
/// POURQUOI CE FICHIER EXISTE, ET CE QU'IL REMPLACE. La détection du tailnet
/// (`DetectionTailscale.adresseDeTailnetPresente`) est une MESURE ponctuelle : on
/// balaie les interfaces (`getifaddrs`) au moment où on la demande. Elle est juste,
/// et elle a corrigé un vrai défaut — mais elle ne dit rien des CHANGEMENTS : si
/// l'utilisateur active Tailscale, coupe le Wi-Fi, passe en 5G ou entre dans une
/// zone blanche, l'application ne l'apprenait qu'à la requête suivante, par son
/// échec ou par son délai dépassé.
///
/// `NWPathMonitor` (Network.framework) donne exactement ce qui manquait : une
/// notification à chaque changement de chemin, avec le type d'interface, le coût et
/// le mode « données réduites ». Il ne dit PAS « ce chemin est le tailnet » — iOS ne
/// publie pas l'état d'un tunnel VPN —, et c'est pourquoi la détection par adresse
/// reste : l'observateur DÉCLENCHE la mesure, il ne la remplace pas.
///
/// CE QUI EST PUR, ET CE QUI NE L'EST PAS. `Etat` est une valeur, et la décision de
/// reprendre (`doitReprendre`) est une fonction pure — donc éprouvée sans réseau,
/// sans VPN et sans attendre un changement. `ObservateurDeChemin` n'est qu'un
/// adaptateur : il traduit un `NWPath` en `Etat` et prévient. C'est ce découpage qui
/// rend la règle vérifiable, comme `Reconnexion` l'est pour les temporisations.
public enum CheminReseau {

  /// Ce qu'on sait du chemin, à un instant donné.
  public struct Etat: Equatable, Sendable {
    /// Le chemin est-il utilisable ? (`NWPath.Status.satisfied`)
    public let disponible: Bool
    /// Le chemin passe-t-il par le cellulaire ?
    public let cellulaire: Bool
    /// Le chemin est-il coûteux (partage de connexion, cellulaire) ?
    public let couteux: Bool
    /// Le mode « données réduites » est-il actif ?
    public let contraint: Bool

    public init(disponible: Bool, cellulaire: Bool = false, couteux: Bool = false, contraint: Bool = false) {
      self.disponible = disponible
      self.cellulaire = cellulaire
      self.couteux = couteux
      self.contraint = contraint
    }

    /// L'état « on ne sait rien encore » : ni disponible, ni mesuré.
    ///
    /// POURQUOI CE N'EST PAS `disponible: true` PAR DÉFAUT. Une application qui
    /// suppose le réseau avant de l'avoir observé prendrait des décisions (reprise,
    /// sondage, rafraîchissement) sur une hypothèse — et le premier `NWPath` réel
    /// les contredirait une seconde plus tard.
    public static let inconnu = Etat(disponible: false)
  }

  /// FAUT-IL REPRENDRE LE TRAVAIL DE FOND ?
  ///
  /// POURQUOI CETTE RÈGLE EST PURE, ET POURQUOI ELLE A DEUX CONDITIONS. Elle a coûté
  /// deux défauts opposés, et les deux sont ici :
  ///
  ///   - **reprendre sans chemin** — rejouer une connexion sur un chemin absent
  ///     consomme un essai du quota de reconnexion pour rien, et c'est exactement ce
  ///     qui brûlait le quota pendant que l'application dormait ;
  ///   - **ne jamais reprendre** — un chemin qui REVIENT (fin de zone blanche,
  ///     Tailscale réactivé) doit relancer ce qui a échoué, sans attendre le
  ///     prochain tic d'une boucle ni le prochain geste de l'utilisateur.
  ///
  /// - Parameters:
  ///   - chemin: l'état OBSERVÉ du chemin.
  ///   - jointe: la cible est-elle déjà jointe ?
  /// - Returns: `true` quand le chemin est là et que la cible manque.
  public static func doitReprendre(chemin: Etat, jointe: Bool) -> Bool {
    chemin.disponible && !jointe
  }

  /// FAUT-IL ESPACER LE SUIVI SUR CE CHEMIN ?
  ///
  /// POURQUOI LA QUESTION SE POSE. Les données réduites et le cellulaire coûtent :
  /// l'utilisateur qui a activé « données réduites » l'a fait pour être ménagé, et
  /// une application qui sonde toutes les trois secondes sur ce chemin va contre sa
  /// décision. On ne COUPE pas le suivi — les pastilles deviendraient fausses —, on
  /// l'espace.
  ///
  /// Rend la cadence À APPLIQUER, à partir de la cadence qu'on aurait eue.
  public static func cadence(chemin: Etat, voulue: TimeInterval) -> TimeInterval {
    if chemin.contraint || chemin.couteux { return max(voulue, 15) }
    return voulue
  }
}

/// L'ADAPTATEUR : traduit `NWPath` en `Etat`, et prévient à chaque changement.
///
/// AUCUNE DÉCISION ICI. Il n'y a donc rien à éprouver sans réseau, et c'est
/// délibéré : tout ce qui se décide est dans `CheminReseau`, au-dessus.
@MainActor
public final class ObservateurDeChemin {
  private let moniteur: NWPathMonitor
  private var continuations: [UUID: AsyncStream<CheminReseau.Etat>.Continuation] = [:]
  private var etatCourant = CheminReseau.Etat.inconnu

  /// L'état observé le plus récent.
  public var etat: CheminReseau.Etat { etatCourant }

  public init() {
    moniteur = NWPathMonitor()
  }

  /// Un flux des états SUCCESSIFS, pour qui veut réagir aux changements.
  public func changements() -> AsyncStream<CheminReseau.Etat> {
    AsyncStream { continuation in
      let cle = UUID()
      continuations[cle] = continuation
      // L'ÉTAT COURANT EST LIVRÉ D'ABORD : un abonné tardif ne doit pas attendre le
      // prochain changement pour savoir où il en est.
      continuation.yield(etatCourant)
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.continuations.removeValue(forKey: cle) }
      }
    }
  }

  public func demarrer() {
    moniteur.pathUpdateHandler = { [weak self] chemin in
      let etat = CheminReseau.Etat(
        disponible: chemin.status == .satisfied,
        cellulaire: chemin.usesInterfaceType(.cellular),
        couteux: chemin.isExpensive,
        contraint: chemin.isConstrained)
      Task { @MainActor in self?.publier(etat) }
    }
    moniteur.start(queue: DispatchQueue(label: "dsh-remote.chemin"))
  }

  public func arreter() {
    moniteur.cancel()
    for continuation in continuations.values { continuation.finish() }
    continuations.removeAll()
  }

  /// Ne publie QUE ce qui change : `NWPathMonitor` rappelle volontiers pour un
  /// chemin identique, et réagir deux fois au même état relancerait deux reprises.
  private func publier(_ etat: CheminReseau.Etat) {
    guard etat != etatCourant else { return }
    etatCourant = etat
    Trace.siActive(
      "[chemin] disponible=\(etat.disponible) cellulaire=\(etat.cellulaire) couteux=\(etat.couteux) contraint=\(etat.contraint)"
    )
    for continuation in continuations.values { continuation.yield(etat) }
  }
}
