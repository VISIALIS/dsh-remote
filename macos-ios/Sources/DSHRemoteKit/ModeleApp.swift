import DSHRemoteKit
import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

#if canImport(Security)
  import Security
#endif

/// État de l'application : une connexion, la liste des sessions, un journal ouvert.
///
/// La vue ne parle jamais au réseau : elle observe ce modèle et lui demande des
/// actions. C'est ce qui permet de tester la logique sans interface, et de
/// remplacer le transport sans toucher aux vues.
@MainActor
@Observable
public final class ModeleApp {
  public var jetonSaisi: String = ""

  public private(set) var sessions: [SessionListee] = []
  public private(set) var journal: [EvenementAffiche] = []
  public private(set) var sessionOuverte: ResumeSession?
  /// Une opération est en cours — un fait d'INTERFACE, pas de connexion : lire
  /// un journal occupe aussi l'écran. Il reste donc un drapeau à part.
  public private(set) var enChargement = false

  /// L'état de la connexion au serveur visé : une valeur, quatre cas.
  ///
  /// POURQUOI UN SEUL TYPE. Cinq champs décrivaient ce même fait — `erreur` (le
  /// texte), `erreurType` (le type), `capacites` (la réponse), `etatAdresse` (le
  /// résultat du test, dans son propre vocabulaire) et `serveurJoint` (un
  /// drapeau) — et leurs combinaisons invalides étaient représentables : une
  /// erreur sans type, un succès sans capacités, « joint » avec une erreur.
  ///
  /// Le texte et le type ont d'ailleurs DIVERGÉ : la classification par texte a
  /// raté le `404` de MacMini, ce qui a fait passer « quelque chose répond mais
  /// pas DSH » pour une panne inconnue. Ici, l'erreur est typée une fois, et son
  /// texte en découle.
  public enum EtatConnexion: Sendable {
    /// Rien n'a été tenté, ou la cible a changé.
    case inconnue
    case enCours
    /// Le serveur a répondu ET accepté le jeton — avec le nombre de sessions
    /// qu'il a rendues, qui est ce que le test d'adresse annonce.
    case jointe(Sante, reponses: Int)
    case echec(ErreurRemote)
    /// On n'a même pas TENTÉ : il manque quelque chose AVANT la requête — jeton
    /// absent, jeton tronqué. Distinct d'un échec réseau, parce que le remède
    /// n'est pas sur le réseau : il est dans la saisie.
    case incomplete(String)
  }

  public private(set) var connexion: EtatConnexion = .inconnue

  // MARK: - La cible : une seule valeur

  /// La CIBLE : la machine que l'application vise, en UNE valeur.
  ///
  /// POURQUOI CE TYPE. Cinq champs la décrivaient — `adresse`, `nomServeur`,
  /// `serveurChoisi`, `echecCible`, `choixAjuste` — écrits depuis dix-sept
  /// endroits. Le journal d'un démarrage réel a montré ce que cela produit :
  /// l'adresse OSCILLE entre deux machines en vingt secondes, parce que la
  /// bascule, la mémorisation et la reconnexion écrivaient chacune la sienne
  /// sans que personne ne voie l'ensemble.
  ///
  /// Ici, la cible se remplace en UN point (`viser`), et cinq transitions
  /// nommées y mènent : `definirAdresse`, `choisir`, `basculer`, `oublier`,
  /// `consigner`. Aucun changement ne peut plus se produire sans passer par un
  /// de ces noms — donc sans être relu à cet endroit.
  ///
  /// CE QUI N'EN FAIT PAS PARTIE : la page ouverte (`serveurOuvert`). Regarder
  /// une machine n'est pas la viser, et les confondre a déjà produit un défaut.
  public struct Cible: Equatable, Sendable {
    public var adresse: String
    /// Nom lisible, quand la machine est connue de la découverte.
    public var nom: String?
    /// La machine de la liste, si l'adresse y correspond.
    public var machine: ServeurMac?
    /// Pourquoi la dernière tentative a échoué — un FAIT constaté, jamais déduit.
    public var echec: EchecCible?
    /// L'avis de bascule, quand l'application a changé de machine elle-même.
    public var avis: String?

    public init(
      adresse: String, nom: String? = nil, machine: ServeurMac? = nil,
      echec: EchecCible? = nil, avis: String? = nil
    ) {
      self.adresse = adresse
      self.nom = nom
      self.machine = machine
      self.echec = echec
      self.avis = avis
    }
  }

  public private(set) var cible = Cible(adresse: ModeleApp.adresseParDefaut)

  /// LE SEUL endroit qui remplace la cible.
  private func viser(_ nouvelle: Cible) {
    cible = nouvelle
  }

  // Les noms historiques restent : les vues les lisent, et rien n'oblige à les
  // renommer pour bénéficier d'une source unique.
  public var adresse: String { cible.adresse }
  public var nomServeur: String? { cible.nom }
  public var serveurChoisi: ServeurMac? { cible.machine }
  public var echecCible: EchecCible? { cible.echec }
  public var choixAjuste: String? { cible.avis }

  /// Le texte de l'échec, DÉRIVÉ du type : les deux ne peuvent plus diverger.
  public var erreur: String? {
    switch connexion {
    case let .echec(erreur): return String(describing: erreur)
    case let .incomplete(detail): return detail
    default: return nil
    }
  }

  /// L'erreur TYPÉE : c'est elle qui décide (« la machine répond mais pas DSH »),
  /// jamais une recherche de code dans un texte.
  public var erreurType: ErreurRemote? {
    if case let .echec(erreur) = connexion { return erreur }
    return nil
  }

  public var capacites: Sante.Capacites? {
    if case let .jointe(sante, _) = connexion { return sante.capacites }
    return nil
  }

  /// Vrai si les sessions affichées viennent bien du serveur visé.
  public var serveurJoint: Bool {
    if case .jointe = connexion { return true }
    return false
  }

  // MARK: - Préférences, PAR SERVEUR

  /// Les deux réglages d'affichage et de suivi d'une machine.
  ///
  /// POURQUOI ILS SONT PAR SERVEUR, ET NON GÉNÉRAUX. Les deux portent sur la
  /// CONNEXION à une machine : le suivi décide si l'on interroge CE serveur
  /// toutes les trois secondes, le filtre décide ce qu'on affiche de SA liste.
  /// Les garder globaux faisait hériter silencieusement chaque serveur des choix
  /// faits pour le précédent — on coupait le suivi pour un Mac endormi, et la
  /// machine suivante ne se rafraîchissait plus sans qu'on sache pourquoi. C'est
  /// exactement le genre de report que le propriétaire a signalé.
  public struct PreferencesServeur: Codable, Equatable, Sendable {
    /// Interroger ce serveur périodiquement (pastilles d'état à jour).
    public var suivi = true
    /// N'afficher de sa liste que les sessions qu'il garde en mémoire.
    public var chargeesSeulement = true

    public init() {}
  }

  /// Clé de stockage : l'ADRESSE NORMALISÉE, seul identifiant stable d'une cible
  /// — une machine peut être nommée, saisie à la main, ou atteinte par son
  /// adresse de tailnet, et c'est la même.
  nonisolated static func cleServeur(_ adresse: String) -> String {
    RemoteClient.normaliser(adresse).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  static let clePreferencesServeurs = "dsh-remote.preferences-serveurs"

  /// Préférences connues, par clé de serveur.
  public private(set) var preferences: [String: PreferencesServeur] = [:]

  /// Préférences d'une adresse — les valeurs par défaut si on ne la connaît pas.
  public func preferences(pour adresse: String) -> PreferencesServeur {
    preferences[ModeleApp.cleServeur(adresse)] ?? PreferencesServeur()
  }

  /// Modifie les préférences d'UN serveur.
  ///
  /// Si c'est le serveur COURANT, l'effet est immédiat : le suivi démarre ou
  /// s'arrête tout de suite. Sinon le réglage attend, et s'appliquera quand on
  /// s'y connectera — ce qui est le sens d'un réglage par serveur.
  public func definirPreferences(pour adresse: String, _ modification: (inout PreferencesServeur) -> Void) {
    let cle = ModeleApp.cleServeur(adresse)
    var valeurs = preferences[cle] ?? PreferencesServeur()
    modification(&valeurs)
    preferences[cle] = valeurs
    memoriserPreferencesServeurs()
    guard cle == ModeleApp.cleServeur(self.adresse) else { return }
    if valeurs.suivi { demarrerSuivi() } else { arreterSuivi() }
  }

  private func chargerPreferencesServeurs() {
    guard let donnees = UserDefaults.standard.data(forKey: Self.clePreferencesServeurs),
      let lues = try? JSONDecoder().decode([String: PreferencesServeur].self, from: donnees)
    else { return }
    preferences = lues
  }

  private func memoriserPreferencesServeurs() {
    guard let donnees = try? JSONEncoder().encode(preferences) else { return }
    UserDefaults.standard.set(donnees, forKey: Self.clePreferencesServeurs)
  }

  /// Le filtre « chargées seulement », POUR LE SERVEUR COURANT.
  public var filtresActifs: Bool { preferences(pour: adresse).chargeesSeulement }

  private var client: RemoteClient?

  /// Macs proposés, découverts au lancement. Vide est un état normal : la
  /// découverte peut échouer des deux côtés (Tailscale absent sur l'hôte, aucun
  /// serveur encore connu), et la saisie manuelle reste toujours disponible.
  public private(set) var serveurs: [ServeurMac] = []

  /// Le serveur dont la PAGE est ouverte, s'il y en a un.
  ///
  /// POURQUOI CE N'EST PAS `serveurChoisi`, ET POURQUOI ÇA A ÉTÉ UN DÉFAUT.
  /// « Choisi » veut dire « celui auquel on se connecte » ; « ouvert » veut dire
  /// « celui qu'on regarde ». Les confondre donnait exactement ce que le
  /// propriétaire a signalé : on touchait MacMini, sa page s'affichait — et
  /// aucune vignette ne le montrait, puisque la coche restait sur la machine
  /// connectée. Deux états, deux signaux.
  ///
  /// L'identifiant est conservé, et non la valeur : la liste est rafraîchie
  /// toutes les quinze secondes, et une valeur capturée afficherait un état
  /// périmé.
  public private(set) var serveurOuvert: String?

  /// Ouvre la page d'une machine. Ne se connecte pas : la connexion est un
  /// bouton de la page.
  public func ouvrirPage(_ serveur: ServeurMac) {
    serveurOuvert = serveur.id
  }


  /// Macs du tailnet qui ont RÉPONDU à la sonde de découverte.
  ///
  /// POURQUOI UNE SONDE, ET POURQUOI ELLE EST NÉCESSAIRE. La découverte liste
  /// tous les Macs du tailnet : elle dit qu'ils sont EN LIGNE, pas qu'ils
  /// servent DSH. Le propriétaire a donc choisi `macmini` — où DSH tournait —
  /// et a reçu « rien n'écoute sur cet hôte et ce port », parce que
  /// `tailscale serve` n'y était pas actif. L'application proposait une machine
  /// sans savoir si elle pouvait répondre.
  ///
  /// Une sonde de santé, courte, le dit. Elle n'est pas gratuite : c'est une
  /// requête vers chaque Mac de la liste. On la paie parce que l'alternative est
  /// une liste qui promet ce qu'elle ne peut pas tenir.
  /// L'état de la sonde : « on ne sait pas », « on interroge », « on sait ».
  ///
  /// POURQUOI UN SEUL TYPE, ALORS QUE TROIS CHAMPS LE DÉCRIVAIENT. Un ensemble
  /// `serveursAvecDsh` accompagné d'un drapeau `sondageEffectue` rendait des
  /// états CONTRADICTOIRES représentables : ensemble vide + drapeau vrai veut
  /// dire « personne ne sert DSH », ensemble vide + drapeau faux veut dire « on
  /// ne sait pas encore ». Deux faits différents dans deux variables qui peuvent
  /// diverger — et elles ont divergé : une sonde ANNULÉE écrivait un verdict
  /// vide, effaçant le bon (mesuré : `fin : 1 DSH` puis `fin : 0 DSH` sans
  /// qu'aucune machine change d'état). Ici, la contradiction ne s'écrit pas.
  public enum EtatSonde: Equatable, Sendable {
    /// Aucune sonde n'a encore rendu de verdict.
    case inconnue
    /// Une sonde est en vol, et on ne savait rien avant elle.
    case enCours
    /// Verdict : les machines qui ont répondu à la sonde.
    case connue(Set<String>)
  }

  public private(set) var sonde: EtatSonde = .inconnue

  #if DEBUG
    // ── CROCHETS DE TEST, ABSENTS DU BINAIRE LIVRÉ ──────────────────────────
    //
    // POURQUOI ILS EXISTENT. Les deux états ci-dessus n'ont qu'un seul écrivain
    // — la sonde, la connexion — et c'est ce qui rend les états contradictoires
    // inécrivables. Ouvrir les propriétés en écriture pour les tests aurait
    // défait exactement ce qu'on vient de gagner. Ces deux fonctions, compilées
    // en DEBUG seulement, permettent d'ÉPROUVER les invariants sans réseau.
    func remplacerSondePourEssai(_ valeur: EtatSonde) { sonde = valeur }
    func remplacerConnexionPourEssai(_ valeur: EtatConnexion) { connexion = valeur }
    /// La liste des machines découvertes, pour éprouver les transitions de la
    /// cible sans dépendre de Tailscale.
    func remplacerServeursPourEssai(_ valeur: [ServeurMac]) { serveurs = valeur }
  #endif

  /// Interroge chaque Mac pour savoir s'il sert DSH.
  ///
  /// Les sondes partent ENSEMBLE : une machine éteinte ne doit pas retarder les
  /// autres. Le délai est court — deux secondes et demie — parce qu'un Mac qui
  /// publie DSH répond en quelques millisecondes sur le tailnet, et qu'un Mac
  /// muet ne mérite pas qu'on l'attende.
  public func sonderLesServeurs() async {
    let jeton = jetonSaisi.isEmpty ? (Self.jetonLocal() ?? "") : jetonSaisi
    // POURQUOI DEUX GARDES SÉPARÉS. Un jeton manquant rend la sonde IMPOSSIBLE :
    // on marque alors l'état comme su, pour que les icônes cessent d'attendre.
    // Mais une liste VIDE n'est pas un verdict — c'est une course : la sonde est
    // lancée par `demarrerDecouverte` avant que Tailscale ait rendu sa liste.
    // La déclarer « effectuée » dans ce cas, c'était empêcher à jamais tout
    // verdict : mesuré, toutes les icônes restaient ORANGE.
    guard jeton.count == 43 else {
      // Sans jeton, aucune sonde n'est possible : ce n'est pas « on ne sait
      // pas », c'est « on sait qu'on ne peut pas » — un verdict vide.
      sonde = .connue([])
      return
    }
    guard !serveurs.isEmpty else { return }
    // ON NE SONDE QUE CE QUI PEUT RÉPONDRE. Interroger une machine que Tailscale
    // dit hors ligne, c'est payer un délai pour un verdict déjà connu — et
    // annoncer « pas de DSH » là où la seule vérité est « elle est éteinte ».
    // Mesuré : la sonde partait sur 3 candidats dont un Mac éteint depuis des
    // mois. Les machines hors ligne ne sont pas sondées, et leur légende reste
    // « hors ligne », ce qui est exactement ce qu'on sait d'elles.
    let candidats = serveurs.filter(\.enLigne)
    guard !candidats.isEmpty else {
      // Aucune machine joignable : verdict vide, et non « inconnu ».
      sonde = .connue([])
      return
    }
    // On ne repasse PAS par « en cours » si un verdict est déjà connu : les
    // légendes ne doivent pas repartir de zéro à chaque rafraîchissement.
    if case .inconnue = sonde { sonde = .enCours }
    // ON NE REMET PAS LE VERDICT À ZÉRO PENDANT UN RAFRAÎCHISSEMENT.
    //
    // `sondageEffectue = false` était posé ici, à chaque sonde — donc toutes les
    // quinze secondes. Les légendes repassaient alors à « vérification… » le
    // temps de la sonde, et l'écran paraissait ne jamais conclure : c'est
    // exactement ce que le propriétaire a photographié deux fois, alors que la
    // sonde rendait son verdict en moins d'une seconde. Un verdict CONNU reste
    // affiché pendant qu'on le rafraîchit ; il n'est remis à « inconnu » que
    // lorsqu'il n'y en a jamais eu.
    let debutSonde = Date()
    print("[sonde] debut : \(candidats.count) candidat(s), deja annulee=\(Task.isCancelled)")

    let trouves = await withTaskGroup(of: (String, Bool).self) { groupe in
      for serveur in candidats {
        groupe.addTask {
          guard let client = try? RemoteClient(adresse: serveur.adresse, jeton: jeton, delai: 2.5)
          else { return (serveur.id, false) }
          // `verifierSante` ne rend aucune donnée de session : c'est la poignée
          // de main. Deux réponses disent que DSH est LÀ : un `200`, et un `401`
          // — car un jeton refusé prouve que le service a répondu. Toute autre
          // erreur (délai, connexion refusée, DNS) veut dire « rien au bout ».
          do {
            _ = try await client.verifierSante()
            return (serveur.id, true)
          } catch ErreurRemote.jetonRefuse {
            return (serveur.id, true)
          } catch {
            return (serveur.id, false)
          }
        }
      }
      var resultat: Set<String> = []
      for await (identifiant, repond) in groupe where repond {
        resultat.insert(identifiant)
      }
      return resultat
    }
    // ── UNE SONDE ANNULÉE N'EST PAS UN VERDICT ──────────────────────────────
    //
    // MESURÉ, ET C'EST UN FAUX NÉGATIF. La sonde est relancée à chaque
    // changement de liste, et SwiftUI ANNULE la précédente. Or une requête
    // annulée lève, le `catch` la range en « pas de DSH », et le groupe rend
    // donc un verdict VIDE — qui écrasait le bon. Le journal de l'application
    // montre exactement la suite : `fin : 1 serveur(s) DSH sur 2`, puis
    // `fin : 0 serveur(s) DSH sur 2`, sans qu'aucune machine ait changé d'état.
    //
    // On ne publie donc un résultat que si la sonde est allée au bout.
    let duree = Int(Date().timeIntervalSince(debutSonde) * 1000)
    guard !Task.isCancelled else {
      print("[sonde] ANNULEE apres \(duree) ms — verdict non publie")
      return
    }
    sonde = .connue(trouves)
    print("[sonde] fin : \(trouves.count) serveur(s) DSH sur \(candidats.count) en \(duree) ms")
  }

  /// Le Mac sert-il DSH, d'après la dernière sonde ?
  ///
  /// `nil` veut dire « pas encore su » — et l'interface ne doit pas transformer
  /// ce doute en affirmation. C'est la leçon de `macmini`.
  public func sertDsh(_ serveur: ServeurMac) -> Bool? {
    // « Pas encore su » : c'est l'ABSENCE de verdict qui compte, pas la
    // présence d'un résultat. Un ensemble vide après une sonde complète est un
    // verdict : aucun Mac ne sert DSH.
    switch sonde {
    case let .connue(ensemble): return ensemble.contains(serveur.id)
    // « En cours » n'est pas un verdict : pendant un rafraîchissement, on rend
    // donc l'ANCIEN, qui reste affiché (voir le commentaire de `sonderLesServeurs`).
    case .inconnue, .enCours: return nil
    }
  }

  /// Empreinte de la liste des serveurs, pour détecter un VRAI changement.
  ///
  /// Sert à relancer la sonde quand la liste arrive — et SEULEMENT là. La sonde
  /// partait jusqu'ici depuis `demarrerDecouverte`, donc quand la liste était
  /// encore vide : le garde-fou la renvoyait, et rien ne la relançait ensuite.
  /// Mesuré : toutes les icônes restaient ORANGE, aucun verdict ne tombait.
  ///
  /// L'empreinte est un ensemble d'identifiants triés : deux listes qui
  /// contiennent les mêmes machines ne déclenchent rien, même si leur état en
  /// ligne a changé — ce qui évite de sonder à chaque rafraîchissement.
  public var empreinteServeurs: String {
    serveurs.map(\.id).sorted().joined(separator: "|")
  }

  /// La machine que vise l'adresse courante, si elle est connue de la liste.
  ///
  /// Rend `nil` pour une adresse saisie à la main : on ne peut rien affirmer
  /// d'une machine qu'on n'a pas découverte.
  public var serveurVise: ServeurMac? {
    ModeleApp.serveurA(adresse: adresse, dans: serveurs)
  }

  /// Version PURE — même normalisation que `serveurHorsLigne`, éprouvable seule.
  nonisolated static func serveurA(adresse: String, dans serveurs: [ServeurMac]) -> ServeurMac? {
    let visee = RemoteClient.normaliser(adresse).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return serveurs.first { serveur in
      RemoteClient.normaliser(serveur.adresse).trimmingCharacters(in: CharacterSet(charactersIn: "/")) == visee
    }
  }

  /// D'où vient la liste affichée.
  ///
  /// Sert à dire la VÉRITÉ sur une liste vide : « l'hôte interrogé ne voit
  /// personne » et « cette plateforme ne peut pas découvrir » ne sont pas le
  /// même constat, et n'appellent pas la même action.
  public enum SourceServeurs: Equatable {
    case aucune
    case tailscaleLocal
    case hote
  }

  public private(set) var sourceServeurs: SourceServeurs = .aucune
  /// Raison d'une liste vide, telle que l'hôte l'a donnée.
  public private(set) var diagnosticServeurs: String?
  private var flux: FluxSession?
  private var tacheFlux: Task<Void, Never>?
  private var tacheSuivi: Task<Void, Never>?
  /// Boucle de synchronisation de la LISTE DES SERVEURS, distincte de celle des
  /// sessions : l'une relit des statuts, l'autre découvre des machines.
  private var tacheServeurs: Task<Void, Never>?

  /// Suivi automatique de la liste : rafraîchit les statuts en continu.
  ///
  /// POURQUOI. Sans lui, les pastilles ne changent qu'au lancement ou par
  /// glissement : le propriétaire a vu « des points bleus partout » alors que le
  /// serveur signalait deux sessions en cours. Un indicateur d'activité qui ne
  /// s'actualise pas est pire qu'aucun indicateur — il donne une image fausse
  /// avec l'autorité d'une mesure.
  ///
  /// Le rafraîchissement est fréquent (3 s) parce qu'il est BON MARCHÉ : la
  /// liste ne relit pas les journaux, elle relit un résumé mis en cache côté
  /// serveur et interroge l'état des agents. On peut le couper.
  /// Le suivi, POUR LE SERVEUR COURANT — la même préférence par serveur que
  /// celle réglée sur sa page.
  public var suiviAutomatique: Bool { preferences(pour: adresse).suivi }

  /// Démarre la boucle de rafraîchissement, si un serveur est joignable.
  public func demarrerSuivi() {
    arreterSuivi()
    guard suiviAutomatique, client != nil else { return }
    tacheSuivi = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }
        guard let self else { return }
        // On ne touche PAS au journal ouvert : seul l'état des sessions est
        // relu, pour ne pas déplacer la lecture sous les yeux de l'utilisateur.
        await self.rafraichirSilencieusement()
      }
    }
  }

  /// Arrête la boucle de rafraîchissement.
  public func arreterSuivi() {
    tacheSuivi?.cancel()
    tacheSuivi = nil
  }

  /// Relit la liste sans afficher d'indicateur de chargement ni d'erreur.
  ///
  /// Un échec passager du suivi ne doit pas effacer l'écran ni signaler une
  /// panne : l'utilisateur n'a rien demandé, il ne doit pas être interrompu.
  private func rafraichirSilencieusement() async {
    guard let client else { return }
    guard let liste = try? await client.listerSessions(limite: 200) else { return }
    sessions = liste.sessions
    observerLesFinsDeTour()
  }

  // MARK: - Rappels de fin

  /// Sessions dont un tour vient de finir sans que l'utilisateur l'ait vu.
  ///
  /// C'est ce qui allume la pastille verte de la liste. La règle complète — et
  /// ses limites — sont dans `RappelsDeFin` : ici on ne fait que lui donner
  /// l'observation et retenir le résultat.
  public private(set) var terminees: Set<String> = []
  private var rappelsDeFin = RappelsDeFin()

  /// Vrai si une fin de tour non vue mérite la pastille verte.
  public func aTermine(_ identifiant: String) -> Bool { terminees.contains(identifiant) }

  /// Confronte la liste reçue à la précédente pour détecter les fins de tour.
  ///
  /// Appelé APRÈS chaque mise à jour de `sessions`, et jamais avant : la règle
  /// compare deux observations successives, donc l'ordre compte.
  private func observerLesFinsDeTour() {
    let observations = sessions.map {
      EtatObserve(identifiant: $0.id, enCours: $0.statut == "en_cours")
    }
    terminees = rappelsDeFin.observer(observations, regardee: sessionOuverte?.id)
  }

  /// Efface le rappel d'une session, parce que l'utilisateur l'a ouverte.
  private func marquerCommeVue(_ identifiant: String) {
    rappelsDeFin.oublier(identifiant)
    terminees.remove(identifiant)
  }

  /// L'utilisateur quitte le journal : la session n'est plus REGARDÉE.
  ///
  /// POURQUOI CE N'EST PAS `fermerJournal`. Vider le journal et couper le flux au
  /// retour ferait clignoter l'écran et perdrait le défilement. Seule change la
  /// réponse à « es-tu en train de regarder cette session ? » — celle qui décide
  /// si une fin de tour mérite une pastille verte. Sans cela, revenir à la liste
  /// laisserait la session marquée « regardée » et son rappel ne s'armerait
  /// jamais : c'est précisément le cas d'usage (lancer un travail, revenir à la
  /// liste, attendre la fin).
  ///
  /// La garde sur l'identifiant évite le piège du changement de session :
  /// SwiftUI peut faire disparaître l'ancienne vue APRÈS avoir ouvert la
  /// nouvelle, et un effacement inconditionnel retirerait celle qu'on vient
  /// d'ouvrir.
  public func quitterJournal(_ identifiant: String) {
    guard sessionOuverte?.id == identifiant else { return }
    sessionOuverte = nil
  }

  /// Vrai quand le suivi temps réel est actif sur la session ouverte.
  public private(set) var enDirect = false
  /// Dernier `seq` reçu par le flux, à repasser en `depuisSeq` si l'on rouvre.
  public private(set) var dernierSeqVu: Int?

  public init() {
    chargerConfiguration()
    chargerPreference()
    chargerPreferencesServeurs()
  }

  /// Mémorise l'adresse et le nom du serveur choisis, entre deux lancements.
  ///
  /// POURQUOI. Ressaisir une adresse de 40 caractères à chaque ouverture est le
  /// genre de friction qui fait abandonner une application. On retient donc le
  /// dernier serveur utilisé.
  ///
  /// CE QUI N'EST PAS MÉMORISÉ ICI : le jeton. Il vit au trousseau sur iOS, qui
  /// est fait pour cela ; `UserDefaults` est un fichier de préférences lisible
  /// par une sauvegarde, ce qui n'est pas un endroit pour un secret.
  private static let cleAdresse = "dsh-remote.derniere-adresse"
  private static let cleNomServeur = "dsh-remote.dernier-nom-serveur"

  private func chargerPreference() {
    let defaults = UserDefaults.standard
    let memorisee = defaults.string(forKey: Self.cleAdresse) ?? ""
    let nom = defaults.string(forKey: Self.cleNomServeur)
    // Sans adresse mémorisée, on garde celle par défaut : le formulaire n'est
    // pas « vidé » au lancement.
    viser(Cible(adresse: memorisee.isEmpty ? cible.adresse : memorisee, nom: nom))
  }

  private func memoriserPreference() {
    let defaults = UserDefaults.standard
    defaults.set(adresse, forKey: Self.cleAdresse)
    if let nomServeur { defaults.set(nomServeur, forKey: Self.cleNomServeur) }
  }

  /// Change l'adresse ET la mémorise immédiatement.
  ///
  /// POURQUOI PAS SEULEMENT APRÈS UNE CONNEXION RÉUSSIE. C'était le défaut :
  /// l'adresse n'était enregistrée que par `connecter()`, donc une tentative
  /// échouée — jeton absent, faute de frappe, serveur éteint — ne laissait
  /// aucune trace, et l'ouverture suivante repartait du champ vide. Or c'est
  /// précisément quand la connexion échoue qu'on veut retrouver son adresse.
  ///
  /// L'adresse n'est pas un secret : la mémoriser à la frappe ne coûte rien.
  /// Le jeton, lui, ne suit PAS ce chemin et reste confié au seul trousseau.
  public func definirAdresse(_ valeur: String) {
    // Le nom et la machine suivent l'adresse : si elle correspond à une machine
    // découverte, on la reconnaît ; sinon on n'affirme RIEN (le nom reste vide,
    // et l'icône se déduit de l'adresse).
    let machine = ModeleApp.serveurA(adresse: valeur, dans: serveurs)
    viser(Cible(adresse: valeur, nom: machine?.nom, machine: machine))
    memoriserPreference()
  }


  /// Symbole du serveur visé, déduit de son nom.
  ///
  /// Tailscale ne rapporte PAS le modèle matériel — `tailscale status --json`
  /// donne le système, pas le châssis. L'icône se déduit donc du NOM, que macOS
  /// construit à partir du modèle (« MacBook Air de … », « MacMini »). C'est une
  /// heuristique d'affichage, assumée : une machine renommée « bureau » retombe
  /// sur l'icône générique, ce qui reste correct.
  public var symboleServeur: String {
    if let nomServeur, !nomServeur.isEmpty {
      return ServeurMac(nom: nomServeur, nomDNS: "", enLigne: true).symbole
    }
    // Repli : le nom d'hôte lui-même, quand il est parlant.
    return ServeurMac(nom: adresse, nomDNS: "", enLigne: true).symbole
  }

  /// Lance la découverte LOCALE hors du fil principal.
  ///
  /// POURQUOI PAS DANS `init`. La découverte exécute un processus
  /// (`tailscale status --json`) : la lancer pendant l'initialisation du modèle
  /// bloquerait l'affichage de la fenêtre tant que le processus n'a pas rendu
  /// la main. L'interface doit s'afficher immédiatement, la liste se remplir
  /// ensuite — ou jamais, sans que cela se voie.
  ///
  /// Sur iPhone, il n'y a rien à lancer : voir `chargerServeursDeLhote()`, qui
  /// interroge le serveur déjà joint — la seule voie possible depuis iOS.
  /// Découverte locale, ATTENDABLE.
  ///
  /// `demarrerDecouverte` lance une tâche détachée : c'est ce qu'il faut pour
  /// l'affichage, pas pour un démarrage qui doit connaître la liste avant de se
  /// connecter. Ici, on attend le résultat.
  public func chargerServeursLocaux() async {
    guard decouverteLocalePossible else { return }
    let trouvees = await Task.detached { DecouverteServeurs.macsDuTailnet() }.value
    let raison = DecouverteServeurs.diagnostic
    guard sourceServeurs != .hote else { return }
    serveurs = trouvees
    diagnosticServeurs = raison
    sourceServeurs = .tailscaleLocal
    relireEtatTailscale()
  }

  public func demarrerDecouverte() {
    guard decouverteLocalePossible else { return }
    Task.detached { [weak self] in
      let trouvees = DecouverteServeurs.macsDuTailnet()
      let raison = DecouverteServeurs.diagnostic
      await MainActor.run {
        guard let self else { return }
        // L'hôte a déjà répondu, et sa liste est plus fraîche que celle d'un
        // processus lancé avant la connexion : on ne l'écrase pas.
        guard self.sourceServeurs != .hote else { return }
        self.serveurs = trouvees
        self.diagnosticServeurs = raison
        self.sourceServeurs = .tailscaleLocal
        // La liste vient d'arriver : c'est le moment de dire si le tailnet
        // fonctionne, et non seulement si Tailscale est installé.
        self.relireEtatTailscale()
        // La sonde ne part PAS d'ici : à cet instant la liste vient d'être
        // posée, mais la vue n'a pas encore été réévaluée. C'est
        // `task(id: modele.empreinteServeurs)` qui s'en charge, et lui seul —
        // un appel ici ne ferait que doubler la sonde.
      }
    }
  }

  /// Demande la liste à l'hôte déjà joint — la voie qui fonctionne sur iPhone.
  ///
  /// Sans bruit en cas d'échec : l'utilisateur n'a rien demandé, et une liste
  /// qui ne vient pas ne doit pas effacer celle qu'il a sous les yeux.
  private func chargerServeursDeLhote() async {
    guard let client else { return }
    guard let liste = try? await client.listerServeurs() else {
      print("[demarrage] liste des serveurs : ECHEC")
      return
    }
    print("[demarrage] liste des serveurs : \(liste.serveurs.count)")
    serveurs = liste.serveurs
    diagnosticServeurs = liste.diagnostic
    sourceServeurs = .hote
    relireEtatTailscale()
    // On demande à chaque Mac s'il sert DSH, plutôt que de le supposer.
    await sonderLesServeurs()
  }

  /// Choisit un serveur et met l'adresse en conséquence.
  ///
  /// L'adresse n'est plus un champ que l'on remplit : elle DÉCOULE du choix.
  /// Le champ reste modifiable pour les cas que la découverte ne couvre pas.
  ///
  /// CHANGER DE SERVEUR VIDE CE QUI VIENT DU PRÉCÉDENT, et c'est un défaut
  /// mesuré : le propriétaire a choisi MacMini, la connexion a échoué, et la
  /// liste a continué d'afficher les 11 sessions de `macbook-air` — avec la
  /// coche sur MacMini. L'écran affirmait donc une chose fausse : que ces
  /// sessions venaient du serveur coché. Une liste qui ne se vide pas quand sa
  /// source change est pire qu'une liste vide : elle est crédible et fausse.
  ///
  /// On vide donc sessions et journal dès que l'adresse visée change vraiment.
  /// La comparaison porte sur l'ADRESSE, pas sur l'identité du serveur : deux
  /// entrées de la découverte peuvent mener à la même machine, et re-vider dans
  /// ce cas ferait clignoter la liste pour rien.
  public func choisir(_ serveur: ServeurMac) {
    // Un avis de bascule ne survit PAS à un choix de l'utilisateur : il
    // racontait ce que l'application avait décidé au démarrage, et il restait
    // affiché ensuite — mesuré : « <adresse> ne répond pas : basculé sur … »
    // sous une liste chargée, alors que plus rien n'était en cause.
    let adresseAvant = adresse
    // Un avis de bascule ne survit PAS à un choix de l'utilisateur : la cible
    // est reconstruite sans lui.
    viser(Cible(adresse: serveur.adresse, nom: serveur.nom, machine: serveur))
    memoriserPreference()
    if adresse != adresseAvant { oublierLesDonneesDeLancienServeur() }
    relireEtatTailscale()
  }

  /// L'application change ELLE-MÊME de machine, et le dit.
  ///
  /// Passe par `choisir` — même transition que l'utilisateur, donc mêmes
  /// conséquences — puis ajoute l'avis, qui est la seule chose en plus.
  private func basculer(sur machine: ServeurMac, avis: String) {
    choisir(machine)
    var nouvelle = cible
    nouvelle.avis = avis
    viser(nouvelle)
  }

  /// Consigne — ou efface — l'échec de la cible courante.
  ///
  /// NE CHANGE QUE L'ÉCHEC. Un échec ne doit jamais changer la machine de
  /// l'utilisateur : c'est exactement ce qu'on a corrigé en exigeant une preuve
  /// avant de basculer. Le seul moyen d'être sûr que cette fonction ne touche
  /// pas à l'adresse, c'est qu'elle ne construise pas de cible nouvelle.
  private func consigner(_ echec: EchecCible?) {
    var nouvelle = cible
    nouvelle.echec = echec
    viser(nouvelle)
  }

  /// Vide ce qui appartenait au serveur précédent.
  ///
  /// Le serveur CHOISI survit : c'est une préférence, pas une donnée. Sans cela,
  /// l'application oublierait la machine qu'on vient de désigner.
  private func oublierLesDonneesDeLancienServeur() {
    arreterSuivi()
    arreterSuiviServeurs()
    arreterFlux()
    client = nil
    // UNE SEULE REMISE À ZÉRO : la connexion porte l'erreur, les capacités, le
    // résultat du test et le fait d'être joint. Les remettre à zéro séparément
    // était quatre occasions d'en oublier une.
    connexion = .inconnue
    sessions = []
    journal = []
    sessionOuverte = nil
    terminees = []
    // On repart de zéro : la liste des machines a changé de source, un verdict
    // sur l'ancienne ne dit rien de la nouvelle.
    sonde = .inconnue
  }

  /// Démarrage : choisir une machine JOIGNABLE, puis se connecter.
  ///
  /// POURQUOI CET ORDRE, ET CE QU'IL CORRIGE. La vue appelait `connecter()` des
  /// l'affichage, sur l'adresse mémorisée — même si la machine était ÉTEINTE.
  /// L'utilisateur voyait donc un échec de transport au lancement, avant d'avoir
  /// rien demandé : mesuré sur ce Mac, à propos d'un MacBook Pro hors ligne
  /// depuis 206 jours. Ajuster APRÈS la connexion ne suffisait pas — l'erreur
  /// était déjà à l'écran.
  ///
  /// On charge donc la liste d'abord, on écarte les machines hors ligne, et on
  /// ne connecte qu'ensuite. Le repli est la boucle locale : sur le Mac qui
  /// exécute le harness, elle répond toujours, et elle est la SEULE source
  /// possible avant qu'un serveur ait été joint (c'est lui qui publie le
  /// tailnet).
  public func demarrer() async {
    if sourceServeurs == .aucune, !decouverteLocalePossible, serveurs.isEmpty {
      // Aucune liste locale possible (iPhone) : on tente l'adresse mémorisée.
      await connecter()
      return
    }
    if decouverteLocalePossible { await chargerServeursLocaux() }
    await ajusterAuParc()
    if serveurChoisi == nil, let hote = serveurs.first(where: \.enLigne) { choisir(hote) }
    guard !adresse.isEmpty else { return }
    await connecter()
  }


  /// Preuve qu'une cible n'aboutit pas : sans elle, on ne bascule PAS.
  ///
  /// POURQUOI CE TYPE EXISTE, ET CE QU'IL A CORRIGÉ. `ajusterAuParc` annonçait
  /// « « <adresse> » ne répond pas : basculé sur … » dès que l'adresse courante
  /// n'était pas une machine DÉCOUVERTE et en ligne — sans qu'aucune requête ait
  /// échoué. Constaté sur capture : l'application était connectée à
  /// `http://127.0.0.1:58674`, cette adresse répondait, et l'écran affichait
  /// quand même qu'elle ne répondait pas. Une adresse saisie à la main, une
  /// adresse de configuration, une instance locale : toutes étaient déclarées
  /// mortes par simple ignorance.
  ///
  /// L'échec est donc CONSIGNÉ là où il est constaté — au refus motivé de
  /// `connecter()` (machine hors ligne) ou à l'échec d'une tentative réelle — et
  /// il est effacé dès qu'une connexion réussit.
  public struct EchecCible: Equatable, Sendable {
    /// Ce qui a été CONSTATÉ, et qui commande la suite.
    public enum Raison: Equatable, Sendable {
      /// La machine est hors ligne sur le tailnet : un fait connu, sans requête.
      case horsLigne
      /// Une tentative réelle n'a pas abouti : délai, DNS, connexion refusée.
      case injoignable
      /// La machine a RÉPONDU, mais rien n'écoute sur son port 80.
      ///
      /// POURQUOI CE CAS NE BASCULE PAS. Il a une cause précise, une explication
      /// et — depuis peu — les commandes qui la corrigent. Basculer sur un autre
      /// Mac effaçait tout cela : le propriétaire voyait un avis de bascule à la
      /// place du seul message qui dise quoi faire sur la machine qu'il venait de
      /// choisir.
      case sansService
    }

    public let adresse: String
    public let raison: Raison
    /// Conservé pour la lisibilité des appelants : `true` seulement pour un fait
    /// du tailnet.
    public var horsLigne: Bool { raison == .horsLigne }
  }


  /// Décision PURE de bascule — éprouvable sans réseau ni état vivant.
  ///
  /// Rend la machine vers laquelle basculer, ou `nil` s'il n'y a rien à faire.
  /// Trois règles, dans cet ordre :
  ///
  ///   1. la cible actuelle est une machine découverte et **en ligne** : on n'y
  ///      touche pas, c'est le choix de l'utilisateur ;
  ///   2. la machine a RÉPONDU mais ne publie rien (`sansService`) : on ne
  ///      bascule pas non plus — le message qui explique quoi faire sur CETTE
  ///      machine serait remplacé par un avis de bascule, et l'utilisateur
  ///      perdrait la seule information utile ;
  ///   3. sinon, il faut une **preuve d'échec** qui concerne l'adresse courante.
  ///      Sans preuve, on ne bascule pas : changer la machine de quelqu'un sur
  ///      une supposition est une substitution silencieuse.
  nonisolated static func cibleDeBascule(
    serveurs: [ServeurMac], choisie: ServeurMac?, echec: EchecCible?, adresse: String
  ) -> ServeurMac? {
    if let choisie, choisie.enLigne, serveurs.contains(where: { $0.id == choisie.id }) { return nil }
    guard let echec, echec.adresse == adresse, echec.raison != .sansService else { return nil }
    return serveurs.first(where: \.enLigne)
  }

  /// Préfère un serveur EN LIGNE à celui qui a été mémorisé — sur preuve.
  ///
  /// POURQUOI CE N'EST PAS UNE TRAHISON DU CHOIX DE L'UTILISATEUR. L'application
  /// mémorise la dernière machine utilisée, et s'y connecte au lancement — même
  /// si elle est ÉTEINTE. Mesuré : au démarrage, un échec de transport
  /// s'affichait avant toute action, à propos d'un Mac hors ligne depuis 206
  /// jours. Un écran d'erreur au lancement n'est pas une information : c'est un
  /// bruit que l'utilisateur n'a pas provoqué.
  ///
  /// On ne bascule PAS silencieusement : on le DIT (`choixAjuste`), et on ne
  /// touche à rien si la machine mémorisée répond. Le choix reste celui de
  /// l'utilisateur dès qu'elle est joignable.
  public func ajusterAuParc() async {
    guard !serveurs.isEmpty else { return }
    guard let enLigne = ModeleApp.cibleDeBascule(
      serveurs: serveurs, choisie: serveurChoisi, echec: echecCible, adresse: adresse)
    else { return }

    // L'avis se calcule AVANT la transition, et sur l'ANCIENNE cible : après,
    // l'échec a été remis à zéro et l'adresse a changé — l'avis parlerait alors
    // de la machine sur laquelle on vient de basculer. C'est exactement ce que
    // le test a attrapé : « ne répond pas » au lieu de « est hors ligne ».
    let visee = echecCible?.adresse ?? adresse
    let etiquette = serveurChoisi?.nom ?? (visee.isEmpty ? "le serveur mémorisé" : visee)
    let horsLigne = echecCible?.raison == .horsLigne
    let avis =
      horsLigne
      ? "« \(etiquette) » est hors ligne sur le tailnet : basculé sur « \(enLigne.nom) », qui est en ligne."
      : "« \(etiquette) » ne répond pas : basculé sur « \(enLigne.nom) », qui est en ligne."

    // UNE SEULE TRANSITION : elle choisit la machine — donc remet l'échec à zéro,
    // car c'est une autre cible — vide les données de l'ancienne, et laisse
    // l'avis. L'erreur affichée ne survit pas non plus.
    basculer(sur: enLigne, avis: avis)
  }

  /// Un appui sur une machine AGIT : il choisit et se connecte, parce que c'est
  /// ce que veut l'utilisateur. S'il manque le jeton, l'erreur le dira et le
  /// champ de jeton est juste au-dessus.
  public func choisirEtConnecter(_ serveur: ServeurMac) async {
    choisir(serveur)
    await connecter()
  }

  /// Vrai quand la découverte LOCALE peut rendre des machines (macOS).
  ///
  /// Sur iPhone, elle est impossible : iOS interdit à une application
  /// d'exécuter un processus. Cela ne condamne pas la liste — l'hôte joint la
  /// publie — mais ce n'est pas cette fonction qui le dit.
  public var decouverteLocalePossible: Bool {
    #if os(macOS)
      return true
    #else
      return false
    #endif
  }

  // MARK: - Suivi automatique des serveurs

  /// Vrai pendant qu'une synchronisation de la liste est en vol.
  public private(set) var synchronisationEnCours = false

  /// Vrai quand le bouton « Ajouter » peut réellement chercher quelque chose.
  ///
  /// Sur iPhone, la découverte locale est impossible : la recherche passe par
  /// l'hôte déjà joint, et demande donc une connexion. Sans elle, le bouton
  /// n'aurait rien à interroger — et un bouton sans effet est un mensonge.
  public var rechercheServeursPossible: Bool {
    client != nil || decouverteLocalePossible
  }

  /// Relit la liste des serveurs SANS intervention de l'utilisateur.
  ///
  /// POURQUOI CE N'EST PLUS UN GESTE MANUEL. Un Mac allumé, une session ouverte
  /// ailleurs, et la liste changeait sans que rien ne le dise : il fallait penser
  /// à rafraîchir. Le geste disparaît donc, comme il a disparu pour les sessions
  /// — la liste se remet à jour toute seule, et la sonde qui dit quels Macs
  /// servent DSH repasse avec elle.
  ///
  /// `synchronisationEnCours` sert de verrou : une synchronisation lente ne doit
  /// pas en empiler une autre toutes les quinze secondes.
  public func synchroniserServeurs() async {
    guard !synchronisationEnCours else { return }
    synchronisationEnCours = true
    defer { synchronisationEnCours = false }

    if client != nil {
      // Les espaces d'abord : un espace créé à l'instant doit apparaître même
      // vide, et c'est ce registre qui porte l'appartenance des sessions.
      if capacites?.espaces == true { await chargerEspacesDeLhote() }
      await chargerServeursDeLhote()
      // L'hôte a répondu — même une liste vide AVEC sa raison : c'est une
      // réponse, on ne la remplace pas par une supposition locale.
      if sourceServeurs == .hote { return }
    }
    await chargerServeursLocaux()
    await relancerSiLaCibleSertDsh()
  }

  /// Efface un échec devenu FAUX, et retente la connexion.
  ///
  /// POURQUOI. L'application affichait — à juste titre — « Aucun service ne
  /// répond sur le port 80 de ce Mac » avec les commandes qui le corrigent. Mais
  /// une fois la commande passée sur l'autre Mac, RIEN ne rejouait la connexion :
  /// le message restait à l'écran alors que la machine servait désormais DSH, et
  /// il fallait appuyer de nouveau sur la machine pour s'en apercevoir.
  ///
  /// La sonde, elle, le sait : elle vient d'interroger cette machine. Quand son
  /// verdict contredit l'erreur affichée, l'erreur disparaît et la connexion est
  /// retentée — c'est le cas où « tout d'un coup, il y arrive ».
  private func relancerSiLaCibleSertDsh() async {
    guard erreur != nil, let vise = serveurVise else { return }
    guard sertDsh(vise) == true else { return }
    await connecter()
  }

  /// Démarre la boucle de synchronisation de la liste des serveurs.
  ///
  /// Quinze secondes : un tailnet ne change pas d'une seconde à l'autre, et
  /// l'interrogation de l'hôte est locale — c'est `tailscale status` d'un côté,
  /// une route JSON de l'autre.
  public func demarrerSuiviServeurs() {
    arreterSuiviServeurs()
    tacheServeurs = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        guard !Task.isCancelled, let self else { return }
        await self.synchroniserServeurs()
      }
    }
  }

  /// Arrête la boucle de synchronisation.
  public func arreterSuiviServeurs() {
    tacheServeurs?.cancel()
    tacheServeurs = nil
  }

  // MARK: - Tailscale

  /// État de Tailscale, relu à la demande et jamais deviné.
  public private(set) var etatTailscale: EtatTailscale = .absent

  /// Relit l'état de Tailscale.
  ///
  /// TROIS SOURCES, ET ELLES NE DISENT PAS LA MÊME CHOSE :
  ///
  ///   1. l'application Tailscale répond-elle à son schéma d'URL ? C'est le
  ///      seul test d'installation possible sur iOS, qui ne publie pas la liste
  ///      des applications installées ;
  ///   2. CET APPAREIL porte-t-il une adresse `100.64.0.0/10` ? C'est la plage
  ///      des adresses de tailnet : sa présence prouve que Tailscale est
  ///      CONNECTÉ, sans rien ouvrir et sans dépendre d'un serveur. Ce test
  ///      remplace l'ancien critère « un serveur répond », qui laissait la carte
  ///      proposer « Ouvrir » — et ce bouton déclenchait le flux
  ///      d'enregistrement d'appareil de Tailscale, qui échouait ;
  ///   3. au moins un serveur est-il en ligne ? C'est ce qui se voit dans la
  ///      liste, mais cela ne dit rien de l'état de Tailscale : le Mac peut être
  ///      éteint alors que le tailnet fonctionne.
  public func relireEtatTailscale() {
    guard DetectionTailscale.applicationInstallee() else {
      etatTailscale = .absent
      return
    }
    if DetectionTailscale.adresseDeTailnetPresente() {
      etatTailscale = .connecte
      return
    }
    etatTailscale = serveurs.contains(where: \.enLigne) ? .connecte : .installe
  }

  /// Exécute l'action de la carte : ouvrir Tailscale, ou son magasin.
  ///
  /// Rend `false` quand rien n'a pu être ouvert. L'appelant le DIT : un appui
  /// qui ne produit rien doit s'expliquer, pas rester muet.
  @discardableResult
  public func ouvrirTailscale() -> Bool {
    DetectionTailscale.ouvrir()
  }

  /// Affiche un message à l'utilisateur, sans toucher au reste de l'état.
  ///
  /// Sert aux actions dont l'échec ne vient d'aucune requête : un `openURL`
  /// refusé, par exemple. Sans ce chemin, l'appui ne produirait rien du tout —
  /// et « rien ne s'est passé » ne doit jamais être une réponse possible.
  public func signaler(_ message: String) {
    // Échec LOCAL, sans requête : la connexion n'est pas en cause, mais c'est
    // bien un « je n'ai pas pu » — et l'écran n'a qu'un endroit pour le dire.
    connexion = .incomplete(message)
  }

  /// L'adresse a répondu, mais le jeton a été refusé.
  ///
  /// Sert à proposer l'action qui répare VRAIMENT : rouvrir les réglages pour
  /// recopier le jeton. Un `401` ne se distingue pas à l'œil d'un `404` ou d'une
  /// panne réseau — sans ce repérage, l'utilisateur cherche une panne là où il
  /// manque un secret, ou l'inverse.
  public var jetonRefuse: Bool {
    switch connexion {
    // Un 401 : le service a répondu, le jeton est refusé.
    case .echec(.jetonRefuse): return true
    // Jeton absent ou tronqué : on n'a même pas tenté.
    case .incomplete: return true
    default: return false
    }
  }

  /// Le serveur choisi est joignable, mais RIEN n'y écoute.
  ///
  /// POURQUOI CE CAS MÉRITE SON PROPRE MESSAGE. C'est le piège le plus coûteux
  /// de cette application, et il a été observé en vrai : la découverte liste
  /// TOUS les Macs du tailnet — elle dit qu'ils sont en ligne, pas qu'ils
  /// publient DSH — et en choisir un qui ne publie rien donne `-1004`, « rien
  /// n'écoute sur cet hôte et ce port ». Le propriétaire a alors soupçonné son
  /// jeton, qui n'y était pour rien.
  ///
  /// Le code `-1004` de `NSURLErrorDomain` veut dire exactement cela : le nom
  /// se résout, la machine répond, mais aucun service n'écoute sur le port.
  public var serveurSansDsh: Bool {
    ModeleApp.repondMaisPasDsh(erreurType)
  }

  /// Vrai quand le port 80 répond AUTRE CHOSE que DSH, au lieu d'être vide.
  ///
  /// Sert au TEXTE, pas à la décision : « rien n'écoute » et « quelque chose
  /// d'autre écoute » ne se disent pas de la même façon, et la seconde
  /// formulation a été fausse dès qu'un `404` est apparu.
  public var portOccupeParAutreChose: Bool {
    if case .reponseInattendue = erreurType { return true }
    return false
  }

  /// Décision PURE : la machine a-t-elle répondu AUTRE CHOSE que DSH ?
  ///
  /// DEUX FORMES, ET LA SECONDE A ÉTÉ MESURÉE APRÈS COUP. La première est
  /// `-1004` — « rien n'écoute sur cet hôte et ce port » : la machine est vivante,
  /// son port 80 est vide. La seconde : le port 80 répond **autre chose**, par
  /// exemple le `404` que `tailscale serve` rend quand il est actif sans publier
  /// DSH. Mesuré sur MacMini : `HTTP/1.1 404 Not Found`, sans en-tête `Server`.
  /// L'application affichait alors « réponse inattendue (HTTP 404) » — un code
  /// technique pour une situation qui a une explication et un remède.
  ///
  /// Dans les deux cas le tailnet fonctionne, le jeton n'y est pour rien, et la
  /// même commande corrige les choses.
  nonisolated static func repondMaisPasDsh(_ erreur: ErreurRemote?) -> Bool {
    switch erreur {
    case let .transport(detail): return detail.contains("-1004")
    case .reponseInattendue: return true
    default: return false
    }
  }

  /// Message affiché quand la liste des Macs est vide.
  ///
  /// Il dépend de la SOURCE, parce que « l'hôte ne voit aucun Mac » et « cette
  /// plateforme ne peut pas en voir » demandent des actions différentes.
  public var messageListeVide: String {
    guard sourceServeurs == .hote else { return DecouverteServeurs.messageDAbsence() }
    if let diagnosticServeurs, !diagnosticServeurs.isEmpty {
      return "Le serveur joint ne voit aucun Mac sur le tailnet (\(diagnosticServeurs)). Saisissez l'adresse ci-dessous."
    }
    return "Le serveur joint ne voit aucun Mac sur le tailnet. Saisissez l'adresse ci-dessous."
  }

  /// Légende d'une machine : son état, et le fait qu'elle soit l'hôte interrogé.
  ///
  /// « Hôte interrogé » et non « cet appareil » : sur iPhone, la machine qui
  /// répond n'est évidemment pas celle qu'on tient en main.
  public func legendeServeur(_ serveur: ServeurMac) -> String {
    let etat = serveur.enLigne ? "en ligne" : "hors ligne"
    return serveur.estLocal ? "hôte interrogé · \(etat)" : etat
  }

  /// État du test d'adresse, pour l'afficher sans ambiguïté.
  public enum EtatAdresse: Equatable {
    case inconnu
    case enCours
    case joignable(reponses: Int)
    case injoignable(String)
  }

  /// Le résultat du test d'adresse, DÉRIVÉ de la connexion : plus de stockage
  /// propre, donc plus moyen de dire autre chose que ce que la connexion dit.
  public var etatAdresse: EtatAdresse {
    switch connexion {
    case .inconnue: return .inconnu
    case .enCours: return .enCours
    case let .jointe(_, reponses): return .joignable(reponses: reponses)
    case let .echec(erreur): return .injoignable(String(describing: erreur))
    case let .incomplete(detail): return .injoignable(detail)
    }
  }

  /// Teste l'adresse saisie en annonçant le résultat.
  ///
  /// POURQUOI CETTE ACTION EXISTE. Le bouton « Rafraîchir la liste » ne pouvait
  /// rien faire sur iPhone : la découverte y est impossible, donc appuyer ne
  /// produisait aucun changement visible, ni succès ni erreur. Un bouton sans
  /// effet est pire qu'un bouton absent. Celui-ci vérifie quelque chose de
  /// réel — l'adresse répond-elle, et le jeton est-il accepté — et le dit.
  public func testerAdresse() async {
    connexion = .enCours
    defer { enChargement = false }
    enChargement = true
    let jeton = jetonSaisi.isEmpty ? (Self.jetonLocal() ?? "") : jetonSaisi
    guard !jeton.isEmpty else {
      connexion = .incomplete("aucun jeton : collez-le d'abord")
      return
    }
    guard jeton.count == 43 else {
      connexion = .incomplete("jeton incomplet : \(jeton.count) caractères au lieu de 43")
      return
    }
    do {
      let client = try RemoteClient(adresse: adresse, jeton: jeton)
      let sante = try await client.verifierSante()
      self.client = client
      let liste = try await client.listerSessions(limite: 200)
      sessions = liste.sessions
      connexion = .jointe(sante, reponses: liste.total ?? liste.sessions.count)
      // Le test d'adresse est aussi une connexion : si l'hôte sait publier la
      // liste des Macs, c'est le moment de la demander.
      if sante.capacites.decouverte == true { await chargerServeursDeLhote() }
    } catch {
      let message = String(describing: error)
      connexion = .echec(error as? ErreurRemote ?? .transport(message))
      journaliserDiagnostic(adresse: adresse, message: message)
    }
  }

  /// Charge une configuration déposée dans le conteneur de l'application.
  ///
  /// POURQUOI CE FICHIER EXISTE. `simctl launch` transmet ses arguments en
  /// `argv`, pas dans l'environnement : les surcharges par variable
  /// d'environnement n'arrivent donc pas à une application iOS, et il n'existe
  /// aucun autre moyen d'amorcer une application non signée sans saisie manuelle.
  /// Ce fichier permet d'ESSAYER l'application sur un simulateur en y déposant
  /// adresse et jeton depuis le Mac.
  ///
  /// PORTÉE RÉELLE : en production, ce fichier n'existe pas — il n'est jamais
  /// créé par l'application, et il doit être déposé explicitement dans un
  /// conteneur de simulateur. Sur un iPhone réel, rien ne le lit.
  private func chargerConfiguration() {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    guard let documents else { return }
    let fichier = documents.appendingPathComponent("dsh-remote-config.json")
    guard let donnees = try? Data(contentsOf: fichier),
      let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: String]
    else { return }
    if let valeur = objet["adresse"], !valeur.isEmpty {
      viser(Cible(adresse: valeur, nom: cible.nom))
    }
    if let valeur = objet["jeton"], valeur.count >= 20 { jetonSaisi = valeur }
  }

  /// Exemple d'adresse à montrer dans le champ vide, selon la plateforme.
  public var adresseExemple: String {
    #if os(macOS)
      return "http://127.0.0.1:3080"
    #else
      return "http://mon-mac.mon-tailnet.ts.net"
    #endif
  }

  /// Vrai si un jeton est disponible, sans jamais le révéler.
  public var jetonDisponible: Bool { !jetonSaisi.isEmpty }

  /// Longueur du jeton en mémoire. Jamais le jeton lui-même.
  public var longueurJeton: Int { jetonSaisi.count }

  /// Empreinte courte du jeton détenu, pour comparer sans le révéler.
  ///
  /// POURQUOI. Le coffre contient DEUX secrets de 43 caractères base64url : le
  /// jeton du plugin et le secret qui signe les cookies du navigateur. Tous deux
  /// passent le contrôle de forme, donc copier le mauvais produit un `401`
  /// indiscernable d'un jeton tronqué. Une empreinte SHA-256 tronquée permet de
  /// dire lequel est détenu, sans jamais exposer la valeur.
  public var empreinteJeton: String {
    guard !jetonSaisi.isEmpty else { return "aucun" }
    return String(Self.empreinte(jetonSaisi).prefix(8))
  }

  /// Empreinte SHA-256 tronquée d'une chaîne. Non réversible.
  static func empreinte(_ valeur: String) -> String {
    let donnees = Data(valeur.utf8)
    var hash = [UInt8](repeating: 0, count: 32)
    donnees.withUnsafeBytes { tampon in
      var accumulateur: UInt64 = 0xcbf29ce484222325
      // Implémentation FNV-1a 64 bits : suffisante pour COMPARER deux valeurs,
      // sans dépendance, et sans prétendre à une résistance cryptographique —
      // ce n'est pas un secret à protéger ici, seulement à distinguer.
      for octet in tampon {
        accumulateur ^= UInt64(octet)
        accumulateur = accumulateur &* 0x100000001b3
      }
      for index in 0..<8 {
        hash[index] = UInt8((accumulateur >> (UInt64(index) * 8)) & 0xff)
      }
    }
    return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  /// Vrai si le jeton a la forme attendue : 43 caractères base64url.
  ///
  /// POURQUOI CE CONTRÔLE EXISTE. Le jeton fait 43 caractères dans un champ
  /// étroit : une saisie ou un collage peut n'en livrer qu'une partie, et rien
  /// ne le montre — l'écran affiche des puces, et le serveur répond seulement
  /// `401`. L'utilisateur cherche alors un problème de droits là où il manque
  /// trois caractères. On refuse donc d'envoyer un jeton dont la forme est
  /// fausse, en disant ce qui ne va pas.
  ///
  /// La forme est un FAIT VÉRIFIABLE (`randomBytes(32)` encodé en base64url),
  /// pas une supposition : le plugin hôte produit exactement cela.
  public var jetonBienForme: Bool {
    jetonSaisi.count == 43 && jetonSaisi.allSatisfy { caractere in
      caractere.isLetter || caractere.isNumber || caractere == "-" || caractere == "_"
    }
  }

  // MARK: - Jeton

  /// Adresse par défaut, surchargeable par l'environnement.
  ///
  /// ELLE DÉPEND DE LA PLATEFORME, et c'est important : `http://127.0.0.1:3080`
  /// est la bonne valeur sur le Mac, où le harness écoute en boucle locale —
  /// mais sur un iPhone, `127.0.0.1` désigne LE TÉLÉPHONE, pas le Mac. Laisser
  /// cette valeur par défaut sur iOS fait échouer la connexion en `-1004`
  /// (« rien n'écoute »), ce qui envoie l'utilisateur chercher une panne
  /// réseau là où le problème est une valeur par défaut trompeuse.
  ///
  /// Sur iOS, le champ part donc VIDE : aucune adresse n'est devinable, et une
  /// valeur fausse est pire qu'une absence de valeur.
  public static var adresseParDefaut: String {
    if let declaree = ProcessInfo.processInfo.environment["DSH_REMOTE_ADRESSE"], !declaree.isEmpty {
      return declaree
    }
    #if os(macOS)
      return "http://127.0.0.1:3080"
    #else
      return ""
    #endif
  }

  /// Lit le jeton d'appareil dans le coffre du harness, si le fichier est là.
  ///
  /// Sur le Mac, l'application et le harness partagent le même utilisateur : le
  /// coffre est lisible et l'utilisateur n'a rien à saisir. Sur iPhone, ce fichier
  /// n'existe pas — `Trousseau.lire()` prend alors le relais, et le jeton a été
  /// saisi une fois puis conservé au trousseau.
  ///
  /// `DSH_REMOTE_COFFRE` force le chemin du coffre, ce qui permet d'essayer
  /// l'application dans le simulateur iOS où `HOME` désigne le conteneur simulé.
  public static func jetonLocal() -> String? {
    let environnement = ProcessInfo.processInfo.environment
    let coffre: URL
    if let force = environnement["DSH_REMOTE_COFFRE"], !force.isEmpty {
      coffre = URL(fileURLWithPath: force)
    } else {
      let base = environnement["DSH_HOME"].flatMap { $0.isEmpty ? nil : $0 }.map { URL(fileURLWithPath: $0) }
        ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")
      coffre = base.appendingPathComponent(".credentials.yaml")
    }
    if let contenu = try? String(contentsOf: coffre, encoding: .utf8),
      let valeur = Self.jetonDuCoffre(contenu)
    {
      return valeur
    }
    return Trousseau.lire()
  }

  /// Extrait le jeton d'appareil du coffre, en ciblant SA clé.
  ///
  /// POURQUOI CE N'EST PAS UN SIMPLE `grep`. Le coffre contient au moins deux
  /// secrets de 43 caractères en base64url : le jeton du plugin, mais aussi le
  /// secret qui signe les cookies de session du navigateur
  /// (`client-connection/browser-session`). Prendre la première ligne « token »
  /// ramassait donc souvent le secret de signature, que le serveur refuse en
  /// `401` — un jeton d'apparence valide, mais qui n'en est pas un.
  ///
  /// On suit donc la structure du document : on n'accepte un `token` que s'il
  /// appartient à l'enregistrement `dsh-remote/device-token`.
  static func jetonDuCoffre(_ contenu: String) -> String? {
    var dansLeBonEnregistrement = false
    for ligne in contenu.split(separator: "\n", omittingEmptySubsequences: false) {
      let texte = ligne.trimmingCharacters(in: .whitespaces)
      if texte.hasPrefix("dsh-remote/") || texte.hasPrefix("records/dsh-remote/") {
        dansLeBonEnregistrement = true
        continue
      }
      // Tout autre enregistrement de premier niveau referme la section.
      if texte.hasSuffix(":") && !texte.hasPrefix("token") && !texte.hasPrefix("payload") {
        if dansLeBonEnregistrement && !texte.contains("device-token") { dansLeBonEnregistrement = false }
      }
      guard dansLeBonEnregistrement, texte.hasPrefix("token:") else { continue }
      let valeur = texte.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
      if valeur.count >= 20 { return valeur }
    }
    return nil
  }

  /// Colle le jeton depuis le presse-papier.
  ///
  /// POURQUOI CE BOUTON. Le jeton fait 43 caractères en base64url, copié depuis
  /// un terminal : à la main, sur un clavier de téléphone, une saisie exacte
  /// est improbable. Le presse-papier supprime le risque de faute — et comme on
  /// nettoie les espaces, un retour à la ligne collé avec la valeur ne gêne pas.
  @discardableResult
  public func collerLeJeton() -> Bool {
    let valeur: String?
    #if canImport(UIKit)
      valeur = UIPasteboard.general.string
    #elseif canImport(AppKit)
      valeur = NSPasteboard.general.string(forType: .string)
    #else
      valeur = nil
    #endif
    guard let valeur else { return false }
    let nettoye = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    guard nettoye.count >= 20 else { return false }
    jetonSaisi = nettoye
    return true
  }

  /// Oublie le serveur mémorisé, adresse comprise.
  ///
  /// Sans cela, une adresse mémorisée par erreur ne pourrait être retirée qu'en
  /// désinstallant l'application.
  public func oublierServeur() {
    arreterSuivi()
    viser(Cible(adresse: ""))
    // Une liste venue de l'hôte n'a plus de source : la garder afficherait les
    // machines d'un serveur qu'on vient d'oublier.
    if sourceServeurs == .hote {
      serveurs = []
      diagnosticServeurs = nil
      sourceServeurs = .aucune
    }
    // Les espaces venaient du serveur oublié : les garder afficherait l'arbre
    // d'une instance qu'on vient de quitter.
    espacesHote = []
    // Sans serveur, plus rien ne prouve que le tailnet fonctionne : on retombe
    // sur « installé », pas sur un état connecté hérité du serveur oublié.
    relireEtatTailscale()
    sessions = []
    journal = []
    sessionOuverte = nil
    connexion = .inconnue
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: Self.cleAdresse)
    defaults.removeObject(forKey: Self.cleNomServeur)
  }

  /// Efface le jeton saisi, en mémoire et au trousseau.
  public func effacerJeton() {
    jetonSaisi = ""
    #if !os(macOS)
      Trousseau.effacer()
    #endif
  }

  /// Enregistre le jeton saisi : au trousseau sur iOS, en mémoire sur macOS.
  ///
  /// N'est appelé qu'à la SOUMISSION du formulaire, jamais à la frappe : un
  /// enregistrement par caractère persistait un jeton tronqué, et faisait
  /// croire à un jeton disponible alors que la saisie n'était pas terminée.
  public func enregistrerJeton(_ valeur: String) {
    jetonSaisi = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    #if !os(macOS)
      if !jetonSaisi.isEmpty { Trousseau.ecrire(jetonSaisi) }
    #endif
  }

  // MARK: - Connexion

  /// Le serveur visé par l'adresse courante, s'il est connu ET hors ligne.
  ///
  /// Rend `nil` quand l'adresse a été saisie à la main : on ne peut rien
  /// affirmer d'une machine qu'on n'a pas vue dans la liste, et une adresse
  /// inconnue mérite une vraie tentative.
  public var serveurViseHorsLigne: ServeurMac? {
    guard let vise = serveurVise, !vise.enLigne else { return nil }
    return vise
  }

  /// Version PURE — éprouvable sans réseau, sans liste vivante et sans attente.
  ///
  /// `nonisolated` À DESSEIN : la décision ne touche aucun état du modèle, elle
  /// ne doit donc pas exiger le fil principal — un test peut l'interroger
  /// directement, sans acteur ni attente.
  nonisolated static func serveurHorsLigne(adresse: String, dans serveurs: [ServeurMac]) -> ServeurMac? {
    guard let vise = serveurA(adresse: adresse, dans: serveurs), !vise.enLigne else { return nil }
    return vise
  }

  /// Message d'ÉTAT pour une machine éteinte — jamais un échec de transport.
  ///
  /// « Délai dépassé, hôte injoignable » décrit ce que le RÉSEAU a fait, pas ce
  /// que l'utilisateur doit faire. Ici l'action est concrète, et elle tient en
  /// une phrase parce que l'état, lui, est connu.
  nonisolated static func messageHorsLigne(_ serveur: ServeurMac) -> String {
    "« \(serveur.nom) » est hors ligne sur le tailnet. Allumez-le, ou choisissez un Mac en ligne : la liste se rafraîchit toute seule."
  }

  public func connecter() async {
    guard !adresse.trimmingCharacters(in: .whitespaces).isEmpty else {
      // Pas d'adresse : ce n'est pas une erreur, c'est un formulaire pas encore
      // rempli. Afficher un échec de transport ici accuserait le réseau à tort.
      connexion = .inconnue
      return
    }
    // ── On ne vise pas une machine que l'on SAIT éteinte ──────────────────────
    //
    // POURQUOI CE GARDE EXISTE, ET CE QU'IL A COÛTÉ. L'application mémorise la
    // dernière machine utilisée et s'y reconnecte au lancement. Le propriétaire a
    // choisi un MacBook Pro ; ce Mac s'est éteint ; à chaque ouverture,
    // l'application lançait donc une requête vers une machine morte, attendait
    // 21 SECONDES (mesuré), puis affichait « échec de transport : délai dépassé,
    // hôte injoignable » — un message technique, pour une machine dont l'écran
    // affichait déjà « hors ligne » juste à côté. Le garde-fou `ajusterAuParc`
    // bascule bien sur un Mac en ligne, mais seulement si la liste est déjà
    // chargée : la requête était partie avant.
    //
    // L'état connu prime donc sur la tentative. Une machine hors ligne n'est pas
    // une panne réseau : c'est une machine éteinte, et cela se dit.
    if let vise = serveurViseHorsLigne {
      // Refus LOCAL : on n'a même pas tenté. Le texte dit l'état et l'action.
      connexion = .incomplete(ModeleApp.messageHorsLigne(vise))
      // L'échec est CONSIGNÉ : c'est la preuve qui autorise `ajusterAuParc` à
      // basculer, et elle dit pourquoi — la machine est hors ligne, ce qui n'est
      // pas la même chose qu'une tentative ratée.
      consigner(EchecCible(adresse: adresse, raison: .horsLigne))
      return
    }
    let jeton = jetonSaisi.isEmpty ? (Self.jetonLocal() ?? "") : jetonSaisi
    guard !jeton.isEmpty else {
      connexion = .incomplete(
        "Aucun jeton d'appareil. Récupérez-le dans la sortie du harness sur le Mac, au premier chargement du plugin.")
      return
    }
    // Un jeton tronqué enverrait une requête vouée au 401, en accusant le
    // serveur à tort : on le dit avant, avec le compte exact.
    guard jeton.count == 43 else {
      connexion = .incomplete("jeton incomplet : \(jeton.count) caractères au lieu de 43. Recopiez-le en entier.")
      return
    }
    // TRACE TEMPORAIRE : ou passe le temps au demarrage.
    let debutConnexion = Date()
    let adresseVisee = adresse
    // Le jeton n'est confié au trousseau qu'ici, une fois la saisie terminée.
    enregistrerJeton(jeton)
    await executer {
      let client = try RemoteClient(adresse: self.adresse, jeton: jeton)
      let sante = try await client.verifierSante()
      self.client = client
      let liste = try await client.listerSessions(limite: 200)
      self.sessions = liste.sessions
      // LE serveur a répondu ET accepté le jeton : une seule valeur le dit —
      // capacités, nombre de sessions rendues, et « joint » en découlent.
      self.connexion = .jointe(sante, reponses: liste.total ?? liste.sessions.count)
      // Première observation : elle ne fait que retenir qui travaille. Une
      // session déjà au repos au chargement ne doit PAS produire de pastille
      // verte — sinon l'application s'ouvrirait sur une liste de faux rappels.
      self.observerLesFinsDeTour()
    }
    print("[demarrage] connecter \(adresseVisee) : \(Int(Date().timeIntervalSince(debutConnexion) * 1000)) ms, erreur=\(erreur == nil ? "non" : "OUI")")
    if erreur == nil {
      // La cible a répondu : plus rien ne justifie de basculer ailleurs.
      consigner(nil)
      demarrerSuivi()
      demarrerSuiviServeurs()
      // Une connexion réussie est le moment où la liste des Macs devient
      // disponible sur iPhone : l'hôte joint, lui, sait voir le tailnet.
      if capacites?.decouverte == true { await chargerServeursDeLhote() }
      // Les espaces de travail viennent du registre de l'hôte : c'est ce qui
      // fait apparaître les dossiers enregistrés mais encore SANS session, que
      // l'application ne pouvait pas représenter en les déduisant des sessions.
      if capacites?.espaces == true { await chargerEspacesDeLhote() }
      relireEtatTailscale()
    } else {
      // Tentative RÉELLE qui a échoué — transport, jeton refusé, version
      // incompatible. C'est une preuve, et elle autorise la bascule.
      //
      // SAUF QUAND LA MACHINE A RÉPONDU : `-1004` veut dire « rien n'écoute sur
      // ce port », donc la machine est vivante et c'est son port 80 qui manque.
      // Ce cas a son propre message, avec les commandes qui le corrigent — on ne
      // l'efface pas en basculant ailleurs.
      let sansService = (erreur ?? "").contains("-1004")
      consigner(EchecCible(adresse: adresse, raison: sansService ? .sansService : .injoignable))
    }
  }

  public func rafraichir() async {
    guard let client else { return }
    await executer {
      let liste = try await client.listerSessions(limite: 200)
      self.sessions = liste.sessions
      self.observerLesFinsDeTour()
    }
    if erreur == nil { demarrerSuivi() }
  }

  public func ouvrir(_ session: SessionListee) async {
    // Ouvrir, c'est voir : le rappel de fin de cette session n'a plus lieu d'être.
    marquerCommeVue(session.id)
    guard let client else { return }
    await executer {
      let journal = try await client.lireSession(
        session.id,
        demande: DemandeJournal(depuis: 0, limite: 400))
      self.sessionOuverte = journal.session
      self.journal = journal.enregistrements.map(DecodeurEvenement.afficher)
    }
    await demarrerFlux(session.id)
  }

  /// Suit la session en direct, en reprenant au dernier `seq` déjà chargé.
  ///
  /// La reprise n'est pas un confort : sans `depuisSeq`, le serveur renverrait
  /// tout ce que la page vient de charger, et le journal afficherait des doublons.
  public func demarrerFlux(_ identifiant: String) async {
    if let precedent = flux { await precedent.fermer() }
    flux = nil
    enDirect = true
    // Simple test d'existence : le client n'est pas utilisé ici, seulement
    // l'adresse et le jeton, relus juste après. `guard let` liait une variable
    // inutile, ce que le compilateur signalait à juste titre.
    guard client != nil else { return }
    let jeton = jetonSaisi
    let adresse = self.adresse
    guard
      let session = FluxSession(
        adresse: adresse, jeton: jeton, identifiant: identifiant,
        depuisSeq: journal.last?.enregistrement.seq)
    else { return }
    flux = session
    let tache = Task { [weak self] in
      for await message in await session.messages() {
        guard let self else { return }
        await self.appliquer(message)
      }
    }
    tacheFlux = tache
  }

  /// Arrête le suivi. Le journal déjà chargé reste affiché.
  public func arreterFlux() {
    tacheFlux?.cancel()
    tacheFlux = nil
    Task { await flux?.fermer() }
    flux = nil
    enDirect = false
  }

  /// Applique un message du flux au journal affiché.
  ///
  /// Un `seq` déjà présent est ignoré : une reprise peut recouvrir la page
  /// chargée, et un doublon à l'écran serait un défaut visible.
  private func appliquer(_ message: MessageFlux) async {
    switch message {
    case let .base(_, enregistrements, _):
      for enregistrement in enregistrements {
        ajouterSiNouveau(enregistrement)
      }
    case let .evenement(enregistrement):
      ajouterSiNouveau(enregistrement)
    case let .delta(dernierSeq):
      if let dernierSeq { dernierSeqVu = dernierSeq }
    case let .tronque(detail):
      connexion = .echec(.transport("Flux incomplet : \(detail)"))
    case let .erreur(detail):
      connexion = .echec(.transport(detail))
      enDirect = false
    }
  }

  private func ajouterSiNouveau(_ enregistrement: EnregistrementJournal) {
    if let seq = enregistrement.seq, journal.contains(where: { $0.enregistrement.seq == seq }) {
      return
    }
    journal.append(DecodeurEvenement.afficher(enregistrement))
  }

  // MARK: - Écriture

  /// Texte en cours de rédaction dans le composeur.
  public var brouillon: String = ""
  /// Un envoi est en vol : le bouton se verrouille, la frappe continue.
  public private(set) var envoiEnCours = false
  /// Acquittement du dernier envoi réussi, affiché sous le champ.
  public private(set) var accuseEnvoi: String?
  /// Motif du dernier refus, en français.
  public private(set) var erreurEcriture: String?

  /// Envoi non encore acquitté : sa règle d'identité vit dans `EnvoiEnAttente`.
  ///
  /// POURQUOI IL EST CONSERVÉ. Un réseau mobile coupe, la réponse se perd, et
  /// l'utilisateur appuie de nouveau. Si chaque tentative tirait un identifiant
  /// neuf, l'hôte insérerait un SECOND message : la conversation afficherait
  /// deux fois la même demande. Tant que l'hôte n'a pas acquitté, on rejoue donc
  /// avec le MÊME identifiant — l'hôte rend alors l'acceptation d'origine.
  private var envoiEnAttente = EnvoiEnAttente()

  /// L'hôte a-t-il annoncé savoir écrire ? Sinon, aucun composeur n'est proposé :
  /// un champ de saisie qui ne peut rien envoyer est un mensonge d'interface.
  public var ecriturePossible: Bool { capacites?.ecriture == true }

  /// L'hôte a-t-il annoncé savoir interrompre un tour ?
  ///
  /// `capacites.ecriture` sert de repli : les deux viennent du même service, et
  /// un hôte qui écrit sans le dire sait annuler.
  public var annulationPossible: Bool {
    capacites?.annulation ?? capacites?.ecriture ?? false
  }

  /// Adresse un message à une session.
  ///
  /// Le texte n'est effacé QU'APRÈS l'acquittement : un échec ne doit jamais
  /// coûter à l'utilisateur ce qu'il vient d'écrire. Le fuseau du client est
  /// joint à la demande — l'hôte le refuse s'il est mal formé, et le journal
  /// situe ainsi l'heure locale de l'auteur.
  public func envoyer(_ session: SessionListee, mode: ModePrompt = .queue) async {
    let texte = brouillon.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !texte.isEmpty, !envoiEnCours, let client else { return }
    let identifiant = envoiEnAttente.identifiant(pour: texte)
    envoiEnCours = true
    defer { envoiEnCours = false }
    do {
      let reponse = try await client.envoyerPrompt(
        session.id,
        demande: DemandePrompt(
          texte: texte, mode: mode, requestId: identifiant,
          fuseau: TimeZone.current.identifier))
      envoiEnAttente.acquitter()
      brouillon = ""
      erreurEcriture = nil
      accuseEnvoi =
        reponse.reprise == true
        ? "accepté — la session était fermée, l'hôte l'a reprise"
        : "accepté — la réponse arrivera dans le journal"
    } catch {
      // Le texte ET l'identifiant restent : rejouer ne créera pas de doublon.
      erreurEcriture = Self.expliquerEcriture(error)
      accuseEnvoi = nil
    }
  }

  /// Interrompt le tour en cours. La file d'attente est conservée.
  public func annulerTour(_ session: SessionListee) async {
    guard let client else { return }
    do {
      let reponse = try await client.annuler(session.id)
      accuseEnvoi = reponse.annule ? "tour interrompu" : nil
      erreurEcriture = reponse.annule ? nil : "l'hôte n'a pas interrompu le tour"
    } catch {
      erreurEcriture = Self.expliquerEcriture(error)
      accuseEnvoi = nil
    }
  }

  /// Efface les messages d'état du composeur (acquittement ou refus).
  public func oublierEtatEcriture() {
    accuseEnvoi = nil
    erreurEcriture = nil
  }

  /// Un tour s'exécute-t-il dans cette session, d'après la dernière liste reçue ?
  ///
  /// La question est posée au MODÈLE et non à la session affichée : l'égalité
  /// d'une `SessionListee` ignore son statut (l'identité d'une session est son
  /// identifiant, sinon la sélection se perdrait à chaque rafraîchissement), donc
  /// une vue qui ne lirait que la valeur reçue ne se redessinerait pas quand
  /// l'agent passe de `inactif` à `en_cours`. Lire `sessions` ici rétablit
  /// l'observation.
  public func estEnCours(_ identifiant: String) -> Bool {
    sessions.first { $0.id == identifiant }?.statut == "en_cours"
  }

  /// Rend une erreur d'écriture lisible, en gardant le motif de l'hôte.
  private static func expliquerEcriture(_ erreur: any Error) -> String {
    if case let ErreurRemote.refusServeur(_, motif, code) = erreur {
      return RefusEcriture.expliquer(code: code, detail: motif, erreur: motif)
    }
    return String(describing: erreur)
  }

  public func fermerJournal() {
    arreterFlux()
    journal = []
    sessionOuverte = nil
  }

  /// Sessions affichées, selon le filtre « vivantes seulement ».
  public var sessionsAffichees: [SessionListee] {
    filtresActifs ? sessions.filter { $0.vivante == true } : sessions
  }

  /// Texte de recherche, appliqué localement aux sessions déjà chargées.
  ///
  /// La recherche porte sur ce que le client POSSÈDE déjà : titre, chemin de
  /// travail, nom d'espace. Elle ne demande rien au serveur, donc elle reste
  /// instantanée même avec plusieurs centaines de sessions — et elle fonctionne
  /// sans que le harness ait à exposer un point d'entrée de recherche.
  public var recherche: String = ""

  /// Sessions retenues après recherche, puis filtre « vivantes ».
  public var sessionsFiltrees: [SessionListee] {
    let retenues = sessionsAffichees
    let terme = recherche.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !terme.isEmpty else { return retenues }
    return retenues.filter { session in
      if session.titreAffiche.lowercased().contains(terme) { return true }
      if let cwd = session.resume.cwd, cwd.lowercased().contains(terme) { return true }
      if let preset = session.resume.preset, preset.lowercased().contains(terme) { return true }
      return false
    }
  }

  /// Sessions regroupées par espace de travail, comme dans l'interface web.
  public var espaces: [EspaceDeTravail] {
    Regroupement.espaces(sessionsFiltrees, hotes: espacesHote)
  }

  /// Espaces de travail publiés par l'hôte, **espaces sans session compris**.
  ///
  /// Vide = « l'hôte n'en publie pas » : on retombe alors sur le regroupement
  /// par `cwd`. C'est le cas d'un hôte plus ancien que cette route, et celui de
  /// l'application avant qu'elle ne la consomme.
  public private(set) var espacesHote: [EspaceHote] = []

  /// Demande ses espaces à l'hôte. Sans bruit : un échec laisse l'arbre tel
  /// qu'il était, plutôt que de le vider sous les yeux de l'utilisateur.
  public func chargerEspacesDeLhote() async {
    guard let client else { return }
    guard let liste = try? await client.listerEspaces() else { return }
    espacesHote = liste.espaces
  }

  private func executer(_ travail: @escaping () async throws -> Void) async {
    enChargement = true
    do {
      try await travail()
      // Le succès est posé par la fermeture : elle seule connaît la réponse
      // (ses capacités, son nombre de sessions). On ne l'écrase pas ici.
    } catch {
      // L'échec est centralisé ici, donc l'état aussi : une seule règle, un seul
      // endroit. L'erreur est TYPÉE, et son texte en découle — les deux ne
      // peuvent plus dire des choses différentes, ce qui est arrivé quand la
      // classification cherchait un code dans un texte.
      let message = String(describing: error)
      connexion = .echec(error as? ErreurRemote ?? .transport(message))
      journaliserDiagnostic(adresse: adresse, message: message)
    }
    enChargement = false
  }

  /// Écrit la dernière erreur de connexion dans le conteneur de l'application.
  ///
  /// POURQUOI. Un message d'erreur affiché à l'écran d'un téléphone est difficile
  /// à rapporter fidèlement, et il ne contient pas toujours le code qui
  /// distingue un refus App Transport Security (`-1022`) d'un DNS injoignable
  /// (`-1003`) ou d'un délai dépassé (`-1001`) — trois causes aux corrections
  /// opposées. Ce fichier permet de lire la cause EXACTE depuis le Mac :
  ///
  ///   xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  ///     --domain-identifier org.example.DSHRemote \
  ///     --source Documents/diagnostic.json --destination /tmp/diagnostic.json
  ///
  /// Il est écrasé à chaque échec : jamais de croissance, jamais d'historique.
  /// Le jeton n'y figure jamais, ni le contenu d'une session.
  private func journaliserDiagnostic(adresse: String, message: String) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return
    }
    let contenu: [String: String] = [
      "adresse": adresse,
      "message": message,
      "date": ISO8601DateFormatter().string(from: Date()),
      // Empreinte seulement : permet de dire SI le jeton détenu est celui du
      // coffre, sans jamais écrire le jeton sur disque.
      "empreinteJeton": empreinteJeton,
      "longueurJeton": String(longueurJeton),
    ]
    guard let donnees = try? JSONSerialization.data(withJSONObject: contenu, options: [.prettyPrinted]) else {
      return
    }
    try? donnees.write(to: documents.appendingPathComponent("diagnostic.json"), options: .atomic)
  }
}

/// Trousseau iOS : le jeton ne doit jamais atterrir dans les préférences, où il
/// serait lisible par une sauvegarde ou un autre composant.
enum Trousseau {
  private static let service = "org.example.dsh-remote"
  private static let compte = "jeton-appareil"

  static func lire() -> String? {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: compte,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
      ]
      var resultat: CFTypeRef?
      guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
        let donnees = resultat as? Data
      else { return nil }
      return String(data: donnees, encoding: .utf8)
    #else
      return nil
    #endif
  }

  static func effacer() {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: compte,
      ]
      SecItemDelete(requete as CFDictionary)
    #endif
  }

  static func ecrire(_ valeur: String) {
    #if canImport(Security)
      let requete: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: compte,
      ]
      SecItemDelete(requete as CFDictionary)
      guard !valeur.isEmpty, let donnees = valeur.data(using: .utf8) else { return }
      var ajout = requete
      ajout[kSecValueData as String] = donnees
      ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      SecItemAdd(ajout as CFDictionary, nil)
    #endif
  }
}
