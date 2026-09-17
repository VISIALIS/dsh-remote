import Foundation

/// LA POLITIQUE DE RECONNEXION DU FLUX : quand rouvrir, et pourquoi.
///
/// POURQUOI ELLE EXISTE, ET CE QU'ELLE CORRIGE. Le protocole du flux a été conçu
/// pour la reprise : `depuisSeq` évite de renvoyer au client ce qu'il possède
/// déjà, et l'hôte fait tout pour qu'une coupure ne coûte rien. Mais le client,
/// lui, s'arrêtait à la première erreur de transport : `appliquer(.erreur)` posait
/// `enDirect = false`, et **il fallait rappuyer sur le bouton**. Sur un iPhone,
/// une bascule Wi-Fi ↔ cellulaire suffisait donc à figer le journal — c'est-à-dire
/// à annuler tout le bénéfice de `depuisSeq`, qui n'existe que pour la reconnexion.
///
/// POURQUOI C'EST UNE VALEUR PURE, ET PAS UNE BOUCLE DANS LA VUE. Une temporisation
/// qui double, qui plafonne et qui se réinitialise ne s'éprouve pas en regardant un
/// écran : il faudrait couper un vrai réseau et attendre. Ici, la règle est une
/// fonction : on lui donne un nombre d'échecs, elle rend un délai. Un test la tient
/// sans réseau, et le modèle ne fait que l'appliquer.
public struct Reconnexion: Sendable, Equatable {

  /// Le délai avant la première nouvelle tentative.
  ///
  /// UNE SECONDE, ET PAS ZÉRO. Réessayer immédiatement après une coupure de
  /// transport est le cas où l'on échoue le plus sûrement : le chemin réseau n'est
  /// pas encore revenu. Une seconde est le temps que met une radio Wi-Fi d'iPhone
  /// à se réveiller — mesuré sur cette installation, où les `ping` du tailnet
  /// passent de 6 ms à 412 ms au réveil.
  public static let delaiInitial: TimeInterval = 1

  /// Le plafond du délai.
  ///
  /// POURQUOI TRENTE SECONDES. Au-delà, une coupure longue ressemblerait à un flux
  /// mort : l'utilisateur regarde un journal qui ne bouge plus. En deçà, une panne
  /// qui dure (hôte redémarré, jeton refusé) produirait cent vingt requêtes par
  /// heure pour rien. Trente secondes tiennent les deux bouts : on ne réessaie pas
  /// trop, et on repart tout seul dès que la machine revient.
  public static let delaiMaximal: TimeInterval = 30

  /// Nombre de tentatives consécutives avant d'ARRÊTER d'insister.
  ///
  /// POURQUOI S'ARRÊTER, ALORS QUE LA REPRISE EST GRATUITE. Parce que le cas le
  /// plus courant d'échec définitif est un **jeton révoqué** (`401`) : il ne se
  /// répare pas en réessayant, et une boucle infinie ferait clignoter l'écran pour
  /// toujours. Après ce nombre de tentatives, le suivi s'arrête et le bouton
  /// reprend la main — c'est un état que l'utilisateur peut comprendre, et qu'il
  /// peut relancer d'un appui.
  ///
  /// VINGT TENTATIVES, à délai doublant puis plafonné, couvrent environ six
  /// minutes : une coupure de réseau réelle, un harness qu'on redémarre ou un Mac
  /// qui se réveille tiennent dans cette fenêtre.
  public static let tentativesMaximales = 20

  /// Le nombre d'échecs consécutifs encaissés jusqu'ici.
  public private(set) var echecs: Int = 0

  public init() {}

  /// Enregistre un échec et rend le délai à observer avant de réessayer.
  ///
  /// Rend `nil` quand il ne faut PLUS réessayer : le quota est épuisé.
  public mutating func echec() -> TimeInterval? {
    echecs += 1
    guard echecs <= Self.tentativesMaximales else { return nil }
    // 1, 2, 4, 8, 16, 30, 30… : la première tentative attend une seconde, et le
    // délai double jusqu'au plafond. Le calcul est fait à partir du rang, et non
    // par accumulation, pour qu'un appel répété ne puisse pas dériver.
    let brut = Self.delaiInitial * pow(2, Double(echecs - 1))
    return min(brut, Self.delaiMaximal)
  }

  /// Un message EST ARRIVÉ : le flux vit, le compteur repart à zéro.
  ///
  /// POURQUOI CE N'EST PAS `echecs = 0` À LA CONNEXION. Une socket qui s'ouvre
  /// puis se referme aussitôt (hôte qui refuse, session inconnue) ne prouve rien :
  /// réinitialiser à l'ouverture ferait boucler à une seconde pour toujours, ce
  /// qui est exactement le martèlement qu'on veut éviter. C'est un CONTENU reçu
  /// qui prouve que le flux fonctionne.
  public mutating func reussite() {
    echecs = 0
  }

  /// Vrai quand le quota d'échecs est épuisé : le suivi doit s'arrêter.
  public var epuisee: Bool { echecs > Self.tentativesMaximales }

  /// Un mot pour l'écran : « Reconnexion… », puis le rang de la tentative.
  public var libelle: String? {
    guard echecs > 0, !epuisee else { return nil }
    return echecs == 1 ? "Reconnexion…" : "Reconnexion \(echecs)/\(Self.tentativesMaximales)…"
  }
}
