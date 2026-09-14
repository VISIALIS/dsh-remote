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

  /// Où les jetons sont gardés — un par hôte.
  private let gardien: GardienDeJetons

  /// Ce qui survit à l'application : adresse mémorisée, préférences par serveur,
  /// fichier d'amorçage, diagnostic. Injectée, donc éprouvable sans disque.
  private let persistance: Persistance
  /// LE CANAL DES ALERTES, injectable : c'est ce qui permet d'éprouver « aucune
  /// alerte quand elles sont éteintes » au lieu de le supposer.
  private let alerteur: Alerteur

  /// COMMENT on demande à une machine si elle sert DSH. La mécanique vit
  /// là-bas ; le modèle garde l'état du verdict et les règles qui l'entourent.
  private let sondeur: Sonde

  /// COMMENT on parle à une machine, et avec quelle patience. La politique vit
  /// là-bas (`Connexion`) ; le modèle garde l'état et les transitions.
  private let transport: Connexion

  /// La clé du dernier jeton CHARGÉ, pour ne pas relire le trousseau à chaque
  /// frappe dans le champ d'adresse (une lecture par caractère, sinon).
  private var cleJetonChargee: String?

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
    /// On n'a même pas TENTÉ, et ce n'est PAS le jeton : la machine est hors
    /// ligne, ou une action locale a échoué (`openURL`). Le remède est ailleurs.
    case incomplete(String)
    /// Le jeton manque, est tronqué, ou a été refusé — le remède est dans la
    /// SAISIE, et c'est ce que la page doit proposer.
    ///
    /// POURQUOI CE CAS EXISTE, ALORS QUE `.incomplete` LE COUVRAIT. `.incomplete`
    /// servait aux deux, et `jetonRefuse` le prenait donc en bloc : la page
    /// affichait « Le service a refusé ce jeton » sur un Mac **éteint**, dont le
    /// jeton n'avait jamais été présenté à personne. Constaté sur capture, sous
    /// la forme de deux avertissements de jeton en tête d'une page qui n'avait
    /// rien joint. Un état qui mélange deux causes produit un remède faux.
    case jetonInvalide(String)
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

  /// Compteur de GÉNÉRATION : incrémenté à CHAQUE changement de cible.
  ///
  /// POURQUOI IL EXISTE. Trois boucles (suivi 3 s, serveurs 15 s, flux) et les
  /// actions de l'utilisateur écrivaient dans le modèle sans que rien ne relie
  /// une réponse à la cible qui l'avait demandée. Une réponse partie vers
  /// l'ANCIENNE machine peut arriver APRÈS une bascule : l'écran afficherait
  /// alors les sessions d'un serveur sous le nom d'un autre. Chaque écriture de
  /// donnée PAR SERVEUR passe donc par un écrivain nommé, qui vérifie que la
  /// réponse concerne encore la cible.
  ///
  /// L'incrément vit dans `viser` — le seul endroit qui remplace la cible. Un
  /// écrivain unique, donc un seul compteur à incrémenter : c'est exactement ce
  /// que l'unification de la cible a rendu possible.
  private var generation = 0

  /// Une réponse asynchrone a-t-elle encore le droit d'écrire ?
  ///
  /// Non si la cible a changé depuis son départ : la réponse décrit une autre
  /// machine, et l'écrire serait montrer les données d'une machine sous le nom
  /// d'une autre.
  func reponseEncoreValable(_ vue: Int) -> Bool { vue == generation }

  /// La génération à confier à une réponse qui part maintenant.
  func generationDuDepart() -> Int { generation }

  /// LE SEUL endroit qui remplace la cible.
  ///
  /// Ellecharge aussi le jeton QUI VA AVEC : puisque chaque hôte a le sien
  /// (mesuré), changer de machine sans changer de jeton enverrait à l'une le
  /// secret de l'autre.
  private func viser(_ nouvelle: Cible) {
    cible = nouvelle
    // La cible a changé : tout ce qui était en vol décrivait l'ancienne.
    generation += 1
    chargerJetonDeLaCible()
  }

  /// Charge, depuis le gardien, le jeton gardé POUR CETTE machine.
  ///
  /// Ne relit que si la clé d'hôte a changé : le champ d'adresse déclenche une
  /// transition par frappe, et une lecture de trousseau par caractère serait un
  /// gaspillage — sans compter les invites système qu'elle peut provoquer.
  private func chargerJetonDeLaCible() {
    let cle = IdentiteHote.cle(cible.adresse)
    guard cle != cleJetonChargee else { return }
    cleJetonChargee = cle
    jetonSaisi = gardien.lire(pour: cle) ?? ""
  }

  /// Le jeton À UTILISER pour la cible : celui gardé POUR ELLE, sinon — et
  /// seulement si la cible EST cette machine — celui du coffre local.
  ///
  /// POURQUOI LE COFFRE N'EST CONSULTÉ QU'ICI. `~/.dsh/.credentials.yaml`
  /// contient le jeton émis par l'hôte LOCAL, et rien d'autre. Le proposer pour
  /// une autre machine, c'était lui envoyer le secret d'une autre — et un refus
  /// qui ne dit pas son nom. Quand on ne sait pas, on ne devine pas : le champ
  /// de jeton est sur la page, à portée.
  public func jetonDeLaCible() -> String {
    // ── LE CHAMP D'ABORD, ET C'EST UNE CORRECTION ──────────────────────────
    //
    // Régression que j'ai introduite en rendant le jeton « par hôte » : cette
    // fonction ne consultait plus `jetonSaisi`, seulement le gardien et le
    // coffre. Or `jetonSaisi` est la valeur la PLUS FRAÎCHE — celle qu'on vient
    // de coller, ou celle qu'un fichier d'amorçage a posée — et elle est déjà
    // rechargée par hôte à chaque changement de cible. Résultat mesuré : l'app
    // démarrait en `0 ms` sans rien tenter, avec « aucun jeton » alors que le
    // champ en contenait un.
    if !jetonSaisi.isEmpty {
      Trace.siActive("[jeton] champ en memoire : longueur=\(jetonSaisi.count) empreinte=\(empreinteJeton)")
      return jetonSaisi
    }
    let cle = IdentiteHote.cle(cible.adresse)
    if let garde = gardien.lire(pour: cle), !garde.isEmpty {
      Trace.siActive(
        "[jeton] gardien de l'hote : longueur=\(garde.count) empreinte=\(Empreinte.de(garde).prefix(8))")
      return garde
    }
    // LE JETON DU COFFRE NE VA QU'À CETTE MACHINE. Le test est `estHoteLocal`, et
    // non `serveurVise?.estLocal` : le second lisait le marqueur d'une liste reçue,
    // donc envoyait le secret local à l'hôte distant qui s'était marqué lui-même.
    guard estHoteLocal(cible.adresse) else {
      Trace.siActive("[jeton] AUCUN jeton pour \(cle)")
      return ""
    }

    let duCoffre = CoffreDuHarness.jetonDeLaMachine() ?? ""
    Trace.siActive(
      "[jeton] coffre du harness : longueur=\(duCoffre.count) empreinte=\(duCoffre.isEmpty ? "aucun" : String(Empreinte.de(duCoffre).prefix(8)))"
    )
    return duCoffre
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
    case let .jetonInvalide(detail): return detail
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

  /// La poignée de main REÇUE, quand une machine est jointe.
  ///
  /// Elle porte ce que les capacités ne disent pas : la PORTÉE du jeton, que
  /// l'hôte est seul à connaître.
  public var santeJointe: Sante? {
    if case let .jointe(sante, _) = connexion { return sante }
    return nil
  }

  /// Vrai si les sessions affichées viennent bien du serveur visé.
  public var serveurJoint: Bool {
    if case .jointe = connexion { return true }
    return false
  }

  // MARK: - Préférences, PAR SERVEUR

  /// Préférences connues, par clé de serveur.
  public private(set) var preferences: [String: PreferencesServeur] = [:]
  /// CE QUI SE RETROUVE À LA RÉOUVERTURE : espaces dépliés, mode d'envoi, session
  /// consultée. Voir `EtatDeNavigation` pour ce qu'il ne contient PAS.
  public private(set) var navigation = EtatDeNavigation()

  /// Préférences d'une adresse — les valeurs par défaut si on ne la connaît pas.
  public func preferences(pour adresse: String) -> PreferencesServeur {
    preferences[IdentiteHote.cle(adresse)] ?? PreferencesServeur()
  }

  /// Modifie les préférences d'UN serveur.
  ///
  /// Si c'est le serveur COURANT, l'effet est immédiat : le suivi démarre ou
  /// s'arrête tout de suite. Sinon le réglage attend, et s'appliquera quand on
  /// s'y connectera — ce qui est le sens d'un réglage par serveur.
  public func definirPreferences(pour adresse: String, _ modification: (inout PreferencesServeur) -> Void) {
    let cle = IdentiteHote.cle(adresse)
    var valeurs = preferences[cle] ?? PreferencesServeur()
    modification(&valeurs)
    preferences[cle] = valeurs
    memoriserPreferencesServeurs()
    guard cle == IdentiteHote.cle(self.adresse) else { return }
    if valeurs.suivi { demarrerSuivi() } else { arreterSuivi() }
  }

  private func chargerPreferencesServeurs() {
    preferences = persistance.lirePreferences()
  }

  private func memoriserPreferencesServeurs() {
    persistance.memoriserPreferences(preferences)
  }

  // MARK: - Ce qui se retrouve à la réouverture

  /// Les espaces dépliés se notent ICI, parce que la vue qui les déplie ne
  /// survit pas à un changement d'onglet ni à un lancement.
  ///
  /// POURQUOI LE MODÈLE S'EN CHARGE, ET NON LA VUE. `@State` meurt avec la vue :
  /// persister depuis elle demanderait d'écrire dans `UserDefaults` au milieu
  /// d'une vue, ce que ce paquet ne fait nulle part. Le modèle est le seul
  /// endroit qui connaît déjà `Persistance`.
  public func definirEspacesDeplies(_ identifiants: Set<String>) {
    // Trié : deux ensembles identiques doivent produire le MÊME enregistrement,
    // sans quoi un test de persistance échouerait au hasard de l'ordre.
    navigation.espacesDeplies = identifiants.sorted()
    persistance.memoriserNavigation(navigation)
  }

  /// Le mode d'envoi se retient d'une session à l'autre — c'est un choix durable.
  public func definirModeEnvoi(_ mode: ModePrompt) {
    navigation.modeEnvoi = mode
    persistance.memoriserNavigation(navigation)
  }

  /// La session dont le journal était ouvert, pour la rouvrir au lancement.
  public func definirSessionConsultee(_ identifiant: String?) {
    // Ne rien réécrire quand rien ne change : cet appel vient d'un `onChange`
    // de sélection, qui se déclenche aussi pour une valeur identique.
    guard navigation.sessionConsultee != identifiant else { return }
    navigation.sessionConsultee = identifiant
    persistance.memoriserNavigation(navigation)
  }

  /// LA SESSION À ROUVRIR, si elle existe encore dans la liste reçue.
  ///
  /// POURQUOI ELLE EST REVALIDÉE. Un identifiant mémorisé peut désigner une
  /// session terminée, archivée, ou appartenant à une autre machine — et rouvrir
  /// un journal qui n'existe plus afficherait un écran vide sous un titre
  /// disparu. On ne rend donc la session que si l'hôte vient de la nommer.
  public var sessionARouvrir: SessionListee? {
    guard let identifiant = navigation.sessionConsultee else { return nil }
    return sessionsFiltrees.first { $0.id == identifiant }
  }

  private func chargerNavigation() {
    navigation = persistance.lireNavigation()
  }

  // MARK: - Les alertes

  /// LES ALERTES SONT ÉTEINTES PAR DÉFAUT, et c'est délibéré : une application qui
  /// réclame le droit d'envoyer des notifications sans qu'on lui ait rien demandé
  /// apprend à être refusée. C'est l'utilisateur qui les allume, et
  /// l'autorisation système n'est demandée QU'À CE MOMENT-LÀ.
  public private(set) var alertesActives = false

  /// La dernière observation connue — `nil` tant qu'aucune liste n'est arrivée.
  private var observationPrecedente:
    (generation: Int, attendent: Set<String>, terminees: Set<String>)?

  /// Allume ou éteint les alertes, en demandant l'autorisation au SYSTÈME quand on
  /// les allume. Rend l'état réellement obtenu : un refus système laisse
  /// l'interrupteur éteint, et l'écran doit le dire plutôt que de mentir.
  @discardableResult
  public func definirAlertes(_ actives: Bool) async -> Bool {
    guard actives else {
      alertesActives = false
      persistance.memoriserAlertes(false)
      return false
    }
    let accordees = await alerteur.demanderAutorisation()
    alertesActives = accordees
    persistance.memoriserAlertes(accordees)
    if !accordees {
      signaler(
        "Les alertes n'ont pas été autorisées. Autorisez-les dans les réglages du système, puis rallumez cet interrupteur.")
    }
    return accordees
  }

  private func chargerAlertes() {
    alertesActives = persistance.lireAlertes()
  }

  /// Le filtre « chargées seulement », POUR LE SERVEUR COURANT.
  public var filtresActifs: Bool { preferences(pour: adresse).chargeesSeulement }

  /// LE FILTRE CACHE-T-IL TOUT CE QUE LE SERVEUR A RENDU ?
  ///
  /// POURQUOI CETTE DISTINCTION EXISTE. Mesure du 13 septembre : le serveur
  /// rendait **156 sessions, dont 8 vivantes**, et le filtre par serveur
  /// « chargées en mémoire seulement » n'en affichait que huit. Quand aucune
  /// n'est en mémoire — juste après un redémarrage du harness — l'arbre est vide
  /// alors que le serveur en connaît cent cinquante-six, et l'écran disait
  /// « Aucune session » : la même phrase que pour un serveur qui n'en a vraiment
  /// aucune. Deux situations, deux phrases — et la seconde propose de tout
  /// afficher.
  public var filtreCacheTout: Bool {
    filtresActifs && !sessions.isEmpty && sessionsAffichees.isEmpty
  }

  /// Montre TOUTES les sessions de ce serveur : le filtre n'a plus rien à cacher.
  public func afficherToutesLesSessions() {
    definirPreferences(pour: adresse) { $0.chargeesSeulement = false }
  }

  /// Le client de la cible jointe. Le type est la SURFACE du port, pas la classe
  /// concrète : le modèle n'a pas à savoir qu'il parle HTTP.
  private var client: (any ClientDSH)?

  /// Macs proposés, découverts au lancement. Vide est un état normal : la
  /// découverte peut échouer des deux côtés (Tailscale absent sur l'hôte, aucun
  /// serveur encore connu), et la saisie manuelle reste toujours disponible.
  public private(set) var serveurs: [ServeurMac] = []

  /// LES ADRESSES DE LA MACHINE QUI EXÉCUTE CETTE APPLICATION — apprises de la
  /// seule découverte LOCALE (voir `appliquerServeursDuTailnet`).
  ///
  /// VIDE SUR IPHONE, et c'est exact : un iPhone n'héberge pas de harness, donc
  /// aucune adresse reçue ne peut être « la sienne ». La boucle locale reste
  /// couverte à part (`ModeleApp.estBoucleLocale`).
  private var adressesDeCetAppareil: Set<String> = []

  /// LES MACHINES TELLES QU'ELLES S'AFFICHENT — joignables d'abord, prêtes en premier.
  ///
  /// POURQUOI CE N'EST PAS `serveurs`. La liste rangée vient de la découverte ou de
  /// l'hôte ; l'ordre d'affichage, lui, dépend d'un fait que cette liste ne porte
  /// pas : le verdict de la SONDE (« cette machine sert DSH »). Le tri se fait donc
  /// à la lecture, sur les deux seuls critères qui comptent — joignable, puis
  /// prête — et JAMAIS sur la sélection.
  ///
  /// LE DÉFAUT QUE LA SÉLECTION A CAUSÉ, ET QUI A ÉTÉ RETIRÉ. Un tri « machine
  /// connectée d'abord » a existé ici : la vignette visée SAUTAIT à l'instant où
  /// on la touchait, puisque le toucher connecte. L'ordre d'une liste qu'on
  /// parcourt du doigt ne doit dépendre que des machines, jamais de ce qu'on vient
  /// de faire.
  public var serveursAffiches: [ServeurMac] {
    DecouverteServeurs.ordonnerPourAffichage(serveurs) { sertDsh($0) == true }
  }

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
  /// TOUCHER UNE MACHINE — la sélectionner, ou ouvrir sa page si elle l'est déjà.
  ///
  /// POURQUOI CE N'EST PAS DANS LA VUE. Deux branches, deux effets très différents
  /// — changer de cible et se reconnecter, ou simplement ouvrir une fiche —, et
  /// QUATRE vignettes les appelaient à la main. Une règle écrite quatre fois finit
  /// par diverger : celle-ci vit dans `GesteSurServeur`, et elle est éprouvée.
  ///
  /// LA PAGE DE L'ANCIENNE MACHINE EST FERMÉE quand on en sélectionne une autre :
  /// sinon `serveurOuvert` continue de désigner la précédente, et le volet de
  /// détail afficherait une machine qui n'est plus visée — le défaut exact que la
  /// règle d'affichage (`DetailAffiche`) rend visible sur macOS et sur iPad.
  public func toucher(_ serveur: ServeurMac) async {
    switch GesteSurServeur.pour(serveur, choisi: serveurChoisi) {
    case .ouvrirLaPage:
      ouvrirPage(serveur)
    case .selectionner:
      fermerPage()
      await choisirEtConnecter(serveur)
    }
  }

  public func ouvrirPage(_ serveur: ServeurMac) {
    serveurOuvert = serveur.id
  }

  /// LA SESSION À LAQUELLE LE JOURNAL APPARTIENT — jamais implicite.
  ///
  /// POURQUOI CETTE CLÉ EXISTE. Le journal et la session ouverte étaient deux
  /// états séparés, et rien ne les liait : une lecture ÉCHOUÉE laissait l'ancien
  /// journal à l'écran pendant que l'en-tête et le titre passaient à la nouvelle
  /// session. L'écran montrait donc les événements d'une session sous le nom
  /// d'une autre — pire qu'un écran vide, parce que rien ne le signalait.
  public private(set) var journalPour: String?
  /// L'ÉCHEC de lecture du journal de cette session, s'il y en a un.
  public private(set) var erreurJournal: String?
  /// La session dont la lecture est EN COURS.
  public private(set) var journalEnLecture: String?

  /// L'erreur de lecture du journal DE CETTE session, s'il y en a une.
  public func erreurJournal(pour identifiant: String) -> String? {
    journalPour == identifiant ? erreurJournal : nil
  }

  /// La lecture du journal de cette session est-elle en cours ?
  public func journalEnLecture(pour identifiant: String) -> Bool {
    journalEnLecture == identifiant
  }

  /// Referme la page d'une machine.
  ///
  /// Sert quand on va AILLEURS — la page « Ajouter un serveur », par exemple :
  /// sans cela, elle serait aussitôt remplacée par celle du serveur resté ouvert.
  public func fermerPage() {
    serveurOuvert = nil
  }


  // MARK: - Les seuls écrivains des collections

  /// Sessions affichées — données d'UN serveur, donc protégées par la génération.
  func appliquerSessions(_ liste: ListeSessions, vu generationVue: Int) {
    guard reponseEncoreValable(generationVue) else { return }
    // LE COMPTE SE TRACE, avec celui des vivantes ET l'état du filtre : « 0
    // session » à l'écran a trois causes très différentes — le serveur n'en rend
    // aucune, la réponse a été refusée (401), ou le filtre « chargées en mémoire
    // seulement » les écarte toutes. Une ligne les distingue, et l'écrivain
    // unique est le seul endroit qui les voie toutes.
    Trace.siActive(
      "[liste] \(liste.sessions.count) session(s), \(liste.sessions.filter { $0.vivante == true }.count) vivante(s), filtre=\(filtresActifs)"
    )
    sessions = liste.sessions
    // L'OBSERVATION APPARTIENT À L'ÉCRIVAIN. Elle était appelée par les trois
    // sites qui écrivent une liste, juste après — un contrat écrit en commentaire
    // (« appelé APRÈS chaque mise à jour de `sessions` ») que rien ne tenait : un
    // quatrième appelant l'aurait oubliée, et les alertes comme les pastilles de
    // fin de tour seraient devenues silencieuses sans que rien ne le dise. Ici,
    // c'est structurel.
    observerLesFinsDeTour()
  }

  /// Journal d'une session — même règle, ET la session en plus.
  ///
  /// POURQUOI LA SESSION EST VÉRIFIÉE ICI. La garde de génération protège d'un
  /// changement d'HÔTE ; elle ne dit rien d'un changement de SESSION. Or les deux
  /// lectures se ressemblent : on ouvre une session, on en ouvre une autre, la
  /// première réponse arrive en retard et s'affiche sous la seconde. Refuser
  /// tout ce qui ne désigne pas la session affichée rend ce mélange impossible.
  func appliquerJournal(_ evenements: [EvenementAffiche], de session: String, vu generationVue: Int) {
    guard reponseEncoreValable(generationVue), journalPour == session else { return }
    journal = evenements
    erreurJournal = nil
  }

  /// Consigne l'échec de lecture du journal DE CETTE session.
  func consignerEchecJournal(_ erreur: any Error, pour session: String) {
    guard journalPour == session else { return }
    erreurJournal = String(describing: erreur)
  }

  /// Espaces déclarés par l'hôte — même règle.
  func appliquerEspaces(_ liste: [EspaceHote], vu generationVue: Int) {
    guard reponseEncoreValable(generationVue) else { return }
    espacesHote = liste
  }

  /// Liste des machines du TAILNET — **sans** garde de génération, et c'est
  /// délibéré : c'est un fait du tailnet, pas une donnée d'un serveur. La jeter
  /// parce que la cible a bougé viderait la liste sous les yeux de l'utilisateur
  /// au moment précis où il choisit une machine.
  private func appliquerServeursDuTailnet(_ liste: [ServeurMac], diagnostic: String?) {
    serveurs = liste
    diagnosticServeurs = diagnostic
    sourceServeurs = .tailscaleLocal
    // LES ADRESSES DE CET APPAREIL, APPRISES ICI ET NULLE PART AILLEURS.
    //
    // POURQUOI CE N'EST PAS `estLocal` LU À LA DEMANDE. Le marqueur `local` d'une
    // liste reçue dit « je suis l'hôte que tu interroges » — pas « je suis la
    // machine qui exécute cette application ». MacMini se marque donc LUI-MÊME
    // local dans sa propre liste, et l'application a cru que son adresse était la
    // sienne : elle lui a présenté le jeton du coffre LOCAL (43 caractères,
    // empreinte `cacde495`, `401` mesuré). Ce que la découverte LOCALE marque
    // `local`, en revanche, est bien CETTE machine — c'est le seul endroit d'où ce
    // fait peut venir, et il est conservé ici.
    adressesDeCetAppareil = Set(
      liste.filter(\.estLocal).map { IdentiteHote.cle($0.adresse) }.filter { !$0.isEmpty })
    relireEtatTailscale()
    // Après une réponse, on n'écrase pas une cible : on rattache seulement.
    assurerUneSelection(auLancement: false, listeVientDeLHote: false)
  }

  /// Liste des machines publiée PAR L'HÔTE — donnée d'un serveur, donc gardée.
  private func appliquerServeursDeLhote(_ liste: ListeServeurs, vu generationVue: Int) {
    guard reponseEncoreValable(generationVue) else { return }
    serveurs = liste.serveurs
    // Le DIAGNOSTIC de l'hôte fait partie de la réponse : sans lui, une liste
    // vide n'explique rien — tailnet vide, Tailscale arrêté, binaire introuvable
    // ne se corrigent pas de la même façon.
    diagnosticServeurs = liste.diagnostic
    sourceServeurs = .hote
    // LE CAS DU DÉFAUT, ET LE SEUL ENDROIT OÙ IL POUVAIT ÊTRE CORRIGÉ. Sur
    // iPhone, cette liste arrive APRÈS la connexion : sans cet appel, la coche
    // n'apparaissait sur aucune vignette et le panneau des espaces restait vide.
    // C'est aussi le seul cas où le marqueur `estLocal` de la liste est un FAIT :
    // l'hôte se désigne lui-même, et c'est lui qu'on interroge.
    assurerUneSelection(auLancement: false, listeVientDeLHote: true)
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
    /// Verdict : les machines qui ont répondu, ET pourquoi les autres non.
    case connue(Sonde.Verdict)
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
    /// Alimenter la liste par la VOIE RÉELLE de la découverte locale : c'est elle
    /// qui apprend quelles adresses sont celles de cet appareil.
    func appliquerServeursDuTailnetPourEssai(_ liste: [ServeurMac], diagnostic: String? = nil) {
      appliquerServeursDuTailnet(liste, diagnostic: diagnostic)
    }
    /// L'invariant « il y a toujours une machine sélectionnée », éprouvé sans
    /// réseau : c'est le même appel que celui des deux endroits où la liste
    /// devient connue.
    func assurerUneSelectionPourEssai(auLancement: Bool, listeVientDeLHote: Bool = false) {
      assurerUneSelection(auLancement: auLancement, listeVientDeLHote: listeVientDeLHote)
    }
    /// Poser le journal d'UNE session SANS RÉSEAU, pour éprouver qu'une réponse
    /// arrivée en retard ne s'affiche pas sous une autre.
    func remplacerJournalPourEssai(_ evenements: [EvenementAffiche], de session: String) {
      journalPour = session
      journal = evenements
      erreurJournal = nil
    }
    /// Consigner un acquittement ou un refus SANS RÉSEAU, pour éprouver qu'un
    /// message ne s'affiche que sous la session qui l'a reçu.
    func consignerEtatEcriturePourEssai(
      session: String, acquittement texteAcquitte: String?, refus texteRefuse: String?
    ) {
      acquittement = texteAcquitte.map { (session: session, texte: $0) }
      refus = texteRefuse.map { (session: session, texte: $0) }
    }
  #endif

  /// POURQUOI CETTE MACHINE NE SERT PAS DSH — pour ELLE, pas pour la connexion
  /// en cours.
  ///
  /// L'ordre compte : si c'est bien elle qu'on visait, la mesure la plus fraîche
  /// est celle de la connexion ; sinon on rend ce que la sonde a observé sur
  /// elle. Et si rien ne l'explique, on ne conclut pas — un jeton refusé veut
  /// dire que le service EST là.
  public func causeSansDsh(_ serveur: ServeurMac) -> CauseSansDsh? {
    if serveurVise?.id == serveur.id, let type = erreurType, let cause = type.causeSansDsh {
      return cause
    }
    if case let .connue(verdict) = sonde { return verdict.causes[serveur.id] }
    return nil
  }

  /// Interroge chaque Mac pour savoir s'il sert DSH.
  ///
  /// Les sondes partent ENSEMBLE : une machine éteinte ne doit pas retarder les
  /// autres. Le délai est court — deux secondes et demie — parce qu'un Mac qui
  /// publie DSH répond en quelques millisecondes sur le tailnet, et qu'un Mac
  /// muet ne mérite pas qu'on l'attende.
  public func sonderLesServeurs() async {
    let jeton = jetonDeLaCible()
    // POURQUOI DEUX GARDES SÉPARÉS. Un jeton manquant rend la sonde IMPOSSIBLE :
    // on marque alors l'état comme su, pour que les icônes cessent d'attendre.
    // Mais une liste VIDE n'est pas un verdict — c'est une course : la sonde est
    // lancée par `demarrerDecouverte` avant que Tailscale ait rendu sa liste.
    // La déclarer « effectuée » dans ce cas, c'était empêcher à jamais tout
    // verdict : mesuré, toutes les icônes restaient ORANGE.
    guard jeton.count == 43 else {
      // Sans jeton, aucune sonde n'est possible : ce n'est pas « on ne sait
      // pas », c'est « on sait qu'on ne peut pas » — un verdict vide.
      sonde = .connue(Sonde.Verdict())
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
      sonde = .connue(Sonde.Verdict())
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
    Trace.siActive("[sonde] debut : \(candidats.count) candidat(s), deja annulee=\(Task.isCancelled)")

    let verdict = await sondeur.interroger(candidats, jeton: jeton)
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
      Trace.siActive("[sonde] ANNULEE apres \(duree) ms — verdict non publie")
      return
    }
    sonde = .connue(verdict)
    Trace.siActive(
      "[sonde] fin : \(verdict.serventDsh.count) serveur(s) DSH sur \(candidats.count) en \(duree) ms, "
        + "\(verdict.causes.count) cause(s) connue(s)")
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
    case let .connue(verdict): return verdict.serventDsh.contains(serveur.id)
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

  /// L'adresse courante désigne-t-elle CETTE machine ?
  ///
  /// Version PURE de « `serveurVise` est ce serveur », qui répond AUSSI pour une
  /// adresse saisie à la main — celle-là n'est dans aucune liste, donc
  /// `serveurVise` vaut `nil` et la comparaison échouerait. Sert à la page d'un
  /// serveur : « Revérifier » reteste l'adresse quand c'est bien elle que
  /// l'application vise — c'est le seul moyen de vérifier une adresse hors
  /// tailnet —, et redemande sinon le verdict de la sonde, sans risque de tester
  /// une AUTRE machine.
  nonisolated static func vise(_ adresse: String, _ serveur: ServeurMac) -> Bool {
    let gauche = RemoteClient.normaliser(adresse).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let droite = RemoteClient.normaliser(serveur.adresse).trimmingCharacters(
      in: CharacterSet(charactersIn: "/"))
    return gauche == droite
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
    // La génération est prise AVANT l'attente : si la cible change pendant que
    // la réponse voyage, elle décrira une autre machine — et l'écrivain la
    // refusera.
    let depart = generationDuDepart()
    guard let liste = try? await client.listerSessions(limite: 200) else { return }
    appliquerSessions(liste, vu: depart)
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
    let termineesAvant = terminees
    terminees = rappelsDeFin.observer(observations, regardee: sessionOuverte?.id)
    prevenirSiNecessaire(termineesAvant: termineesAvant)
  }

  /// LES ALERTES PARTENT D'ICI, et d'ici seulement : c'est le seul endroit qui
  /// voit DEUX observations successives, donc le seul qui puisse dire ce qui a
  /// CHANGÉ.
  ///
  /// POURQUOI LA PREMIÈRE OBSERVATION N'ALERTE PAS. Au lancement, la liste arrive
  /// complète : sans cette règle, trois sessions déjà bloquées produiraient trois
  /// alertes pour un état que l'utilisateur voit à l'écran. `observationPrecedente`
  /// vaut `nil` tant qu'aucune liste n'a été reçue, et c'est ce `nil` qui
  /// distingue « tout est nouveau » de « rien n'a changé ».
  private func prevenirSiNecessaire(termineesAvant: Set<String>) {
    let attendent = Set(sessions.filter { $0.attendReponse == true }.map(\.id))
    let precedente = observationPrecedente
    observationPrecedente = (generation: generation, attendent: attendent, terminees: terminees)
    // LA GÉNÉRATION FAIT PARTIE DE LA COMPARAISON. Après un changement de
    // machine, la première liste du nouvel hôte ne compare rien : elle retient.
    // Sans cela, trois sessions déjà bloquées ailleurs produiraient trois alertes
    // pour un état que personne n'a vu commencer.
    guard alertesActives, let precedente, precedente.generation == generation else { return }

    let alertes = Alerte.aEnvoyer(
      attendent: attendent,
      attendaientAvant: precedente.attendent,
      terminees: terminees,
      termineesAvant: termineesAvant,
      regardee: sessionOuverte?.id)
    guard !alertes.isEmpty else { return }
    Task { [alerteur] in
      for alerte in alertes { await alerteur.prevenir(alerte) }
    }
  }

  /// Efface le rappel d'une session, parce que l'utilisateur l'a ouverte.
  ///
  /// PUBLIQUE DEPUIS LES GESTES DE LISTE, et pour une raison précise : le
  /// rappel de fin se consommait uniquement en OUVRANT la session, ce qui était
  /// le seul moyen de dire « j'ai vu ». Le glissement et le menu contextuel
  /// offrent maintenant l'action sans quitter la liste — et sans elle, ils
  /// n'auraient rien à proposer que du copier.
  public func marquerCommeVue(_ identifiant: String) {
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
    // LE JOURNAL CHARGÉ RESTE, et sa clé avec lui : revenir sur la session le
    // retrouve tel quel, sans le relire. Ce qui s'arrête ici est la VEILLE —
    // le rappel de fin peut de nouveau s'armer.
  }

  /// Vrai quand le suivi temps réel est actif sur la session ouverte.
  public private(set) var enDirect = false
  /// Dernier `seq` reçu par le flux, à repasser en `depuisSeq` si l'on rouvre.
  public private(set) var dernierSeqVu: Int?

  public init(
    gardien: GardienDeJetons = GardienParDefaut.faire(),
    persistance: Persistance = Persistance(),
    alerteur: Alerteur = AlerteurSysteme(),
    transport: Connexion = Connexion(),
    sondeur: Sonde = Sonde()
  ) {
    self.gardien = gardien
    self.persistance = persistance
    self.alerteur = alerteur
    self.transport = transport
    self.sondeur = sondeur
    chargerConfiguration()
    chargerPreference()
    chargerPreferencesServeurs()
    chargerNavigation()
    chargerAlertes()
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
  private func chargerPreference() {
    let (memorisee, nom) = persistance.lireAdresse()
    // Sans adresse mémorisée, on garde celle par défaut : le formulaire n'est
    // pas « vidé » au lancement.
    viser(Cible(adresse: memorisee.isEmpty ? cible.adresse : memorisee, nom: nom))
  }

  private func memoriserPreference() {
    persistance.memoriserAdresse(adresse, nom: nomServeur)
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
    let trouvees = await Task.detached { DecouverteServeurs.machinesDuTailnet() }.value
    let raison = DecouverteServeurs.diagnostic
    // L'hôte a déjà répondu, et sa liste est plus fraîche : on ne l'écrase pas.
    guard sourceServeurs != .hote else { return }
    appliquerServeursDuTailnet(trouvees, diagnostic: raison)
  }

  public func demarrerDecouverte() {
    guard decouverteLocalePossible else { return }
    Task.detached { [weak self] in
      let trouvees = DecouverteServeurs.machinesDuTailnet()
      let raison = DecouverteServeurs.diagnostic
      await MainActor.run {
        guard let self else { return }
        // L'hôte a déjà répondu, et sa liste est plus fraîche que celle d'un
        // processus lancé avant la connexion : on ne l'écrase pas.
        guard self.sourceServeurs != .hote else { return }
        self.appliquerServeursDuTailnet(trouvees, diagnostic: raison)
        // La liste vient d'arriver : c'est le moment de refaire les constats
        // locaux sur Tailscale, qui décident de la première étape du parcours.
        self.relireEtatTailscale()
        // La sonde ne part PAS d'ici : à cet instant la liste vient d'être
        // posée, mais la vue n'a pas encore été réévaluée. C'est
        // `task(id: modele.empreinteServeurs)` qui s'en charge, et lui seul —
        // un appel ici ne ferait que doubler la sonde.
      }
    }
  }

  /// Un client pour les routes qui font travailler l'HÔTE, au délai plus long.
  ///
  /// POURQUOI UN CLIENT À PART. Ces routes interrogent le CLI Tailscale de
  /// l'hôte, qui borne son propre appel à huit secondes. Le client de connexion
  /// coupe à huit : il couperait exactement ce que l'hôte s'autorise. On ne parle
  /// à l'hôte que si on l'a déjà joint — `client` en est la preuve.
  /// L'hôte ne se demande QUE si on l'a déjà joint — `client` en est la preuve.
  private var hoteEstJoint: Bool { client != nil && !adresse.isEmpty }

  /// Demande la liste à l'hôte déjà joint — la voie qui fonctionne sur iPhone.
  ///
  /// Sans bruit en cas d'échec : l'utilisateur n'a rien demandé, et une liste
  /// qui ne vient pas ne doit pas effacer celle qu'il a sous les yeux.
  private func chargerServeursDeLhote() async {
    guard hoteEstJoint else { return }
    guard let liste = try? await transport.serveursDeLhote(adresse: adresse, jeton: jetonDeLaCible())
    else {
      Trace.siActive("[demarrage] liste des serveurs : ECHEC")
      return
    }
    Trace.siActive("[demarrage] liste des serveurs : \(liste.serveurs.count)")
    appliquerServeursDeLhote(liste, vu: generationDuDepart())
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

  /// ATTACHE À LA CIBLE LA MACHINE QU'ON VIENT DE RECONNAÎTRE — sans changer de cible.
  ///
  /// POURQUOI CE N'EST PAS `viser`, ET POURQUOI ÇA COMPTE. `viser` remplace la
  /// cible et incrémente la génération, ce qui JETTE les réponses en vol. Ici
  /// l'adresse ne change pas, la machine non plus : on ajoute seulement le fait
  /// qu'on sait LAQUELLE c'est. Passer par `viser` ferait disparaître la liste des
  /// sessions qui arrive au même moment — et l'écran resterait vide jusqu'au
  /// cycle suivant, quinze secondes plus tard.
  private func attacherLaMachine(_ machine: ServeurMac) {
    guard cible.machine?.id != machine.id else { return }
    cible.machine = machine
    cible.nom = machine.nom
    memoriserPreference()
  }

  /// GARANTIT QU'UNE MACHINE EST SÉLECTIONNÉE DÈS QU'IL Y EN A UNE.
  ///
  /// LA RÈGLE EST DANS `SelectionParDefaut`, et elle est éprouvée là-bas : la
  /// machine jointe d'abord (un fait), la première de la liste affichée ensuite —
  /// mais seulement au lancement, jamais après une réponse de l'hôte.
  ///
  /// ELLE EST APPELÉE LÀ OÙ LA LISTE DEVIENT CONNUE, et pas seulement au
  /// démarrage : sur iPhone, c'est la réponse de l'hôte qui apporte la liste,
  /// donc bien après le début du lancement. C'est exactement l'ordre qui cachait
  /// le défaut : la coche n'apparaissait jamais, et les espaces de travail non
  /// plus.
  func assurerUneSelection(auLancement: Bool, listeVientDeLHote: Bool) {
    if cible.machine == nil {
      let liste = serveursAffiches
      if let reconnue = SelectionParDefaut.aSelectionner(
        parmi: liste, adresse: adresse, listeVientDeLHote: listeVientDeLHote,
        remplacerFauteDeMieux: auLancement)
      {
        switch reconnue {
        case let .jointe(machine), let .hote(machine):
          // ON ATTACHE, ON NE REMPLACE PAS — dans les DEUX cas, y compris quand
          // l'adresse diffère. C'est ce que l'hôte qui se désigne lui-même a
          // appris au simulateur : remplacer l'adresse de boucle locale par celle
          // du tailnet a vidé les six sessions et les sept espaces de travail qui
          // venaient d'être chargés, pour la seule raison qu'on changeait
          // d'écriture d'adresse.
          attacherLaMachine(machine)
        case let .premiere(machine):
          // Là seulement, la cible est REMPLACÉE : au lancement, l'adresse
          // courante ne désigne personne, et la première machine de la liste est
          // le meilleur choix — l'appelant se connecte juste après.
          choisir(machine)
        }
      }
    }
    // AU LANCEMENT, LA PAGE DE LA MACHINE SÉLECTIONNÉE EST OUVERTE : l'écran de
    // droite ne reste pas vide, il explique la machine qu'on a sous les yeux.
    //
    // POURQUOI CE N'EST PAS DANS LE BLOC CI-DESSUS, ET CE QUE LA CAPTURE A MONTRÉ.
    // Le chargeur de liste (`chargerServeursLocaux`) appelle le même invariant
    // AVANT le démarrage : la machine est donc DÉJÀ attachée quand on arrive ici,
    // le bloc ne s'exécute pas, et le volet affichait l'écran de sélection au lieu
    // de la page — vu à l'écran, pas déduit. L'ouverture doit donc dépendre de
    // l'état, pas du chemin qui y a mené.
    //
    // AILLEURS ON N'OUVRE RIEN : un appui sur une autre vignette sélectionne et
    // recharge ses sessions et ses espaces, et c'est le SECOND appui qui ouvre.
    if auLancement, serveurOuvert == nil, let choisie = serveurChoisi { ouvrirPage(choisie) }
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
    viderLeJournal()
    terminees = []
    // LES ESPACES DE TRAVAIL SONT UNE DONNÉE DU SERVEUR, PAS DE L'APPLICATION.
    // Ils venaient du registre de l'hôte PRÉCÉDENT, et ils survivaient au
    // changement de machine : la liste latérale montrait donc les dossiers de
    // l'ancien serveur, mêlés aux sessions du nouveau — ou seule, si la
    // connexion au nouveau échouait. Le rechargement a lieu dès que la nouvelle
    // cible est jointe (`chargerEspacesDeLhote`) ; ici, on efface, parce que ce
    // qui reste à l'écran entre les deux décrit une machine qui n'est plus visée.
    espacesHote = []
    // LA LISTE DES MACS, ELLE, N'EST PAS TOUCHÉE — et c'est délibéré, comme le
    // dit `appliquerServeursDuTailnet` : c'est un fait du TAILNET, pas une donnée
    // d'un serveur. La vider ici la ferait disparaître au moment précis où
    // l'utilisateur s'en sert — il vient de cliquer une machine de cette liste.
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
    // AU LANCEMENT, ET LÀ SEULEMENT, on peut remplacer faute de mieux : la liste
    // affichée est en ligne d'abord, donc « le premier » est le premier joignable.
    assurerUneSelection(auLancement: true, listeVientDeLHote: false)
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

  /// CET APPAREIL est-il sur le tailnet ? Une CONSTATATION : il porte une adresse
  /// dans `100.64.0.0/10`.
  ///
  /// POURQUOI CE N'EST PAS « un serveur est en ligne ». Un serveur en ligne peut
  /// venir de la liste publiée par un AUTRE hôte, qui ne dit rien de cet
  /// appareil-ci ; et un Mac éteint ne dit rien de Tailscale. La première étape
  /// du parcours mérite la mesure directe.
  ///
  /// `nil` TANT QU'ON N'A PAS MESURÉ, et ce n'est pas un détail : un `false` par
  /// défaut affichait « à faire » pour une étape que personne n'avait constatée.
  /// Constaté sur une capture, où l'ancre `--page-seule` court-circuite le
  /// démarrage : le parcours affirmait que Tailscale n'était pas connecté alors
  /// que le Mac l'était.
  public private(set) var tailnetDeLAppareil: Bool?

  /// L'application Tailscale est-elle présente sur cet appareil ?
  ///
  /// Sert à dire QUOI FAIRE : l'installer, ou l'ouvrir pour se connecter.
  public private(set) var tailscaleInstalle = false

  /// Relit l'état de Tailscale.
  ///
  /// DEUX CONSTATATIONS, ET AUCUNE DÉDUCTION :
  ///
  ///   1. l'application Tailscale répond-elle à son schéma d'URL ? C'est le seul
  ///      test d'installation possible sur iOS, qui ne publie pas la liste des
  ///      applications installées ;
  ///   2. CET APPAREIL porte-t-il une adresse `100.64.0.0/10` ? C'est la plage
  ///      des adresses de tailnet : sa présence prouve que Tailscale est
  ///      CONNECTÉ, sans rien ouvrir et sans dépendre d'un serveur.
  ///
  /// Un troisième état vivait ici — « l'application est là, mais aucun serveur ne
  /// répond » —, et il est parti avec la CARTE qui seule le lisait : ce que ce
  /// cas décrivait n'était pas l'état de Tailscale, mais celui de la liste des
  /// Macs, que le panneau latéral montre déjà (`resumeServeurs`, la légende de
  /// chaque vignette).
  public func relireEtatTailscale() {
    // LES DEUX CONSTATATIONS SONT RETENUES, et elles servent toutes les deux : le
    // parcours d'un serveur a besoin de savoir si CET APPAREIL est sur le tailnet
    // (première étape) et si l'application y est installée (pour dire quoi faire
    // quand elle ne l'est pas). Les recalculer dans la vue les ferait diverger.
    tailscaleInstalle = DetectionTailscale.applicationInstallee()
    tailnetDeLAppareil = DetectionTailscale.adresseDeTailnetPresente()
  }

  /// Ouvre Tailscale, ou son magasin quand l'application manque.
  ///
  /// Appelé par la PREMIÈRE étape du parcours d'un serveur — c'est le seul
  /// endroit qui propose l'action, depuis que la carte du panneau latéral est
  /// partie. Rend `false` quand rien n'a pu être ouvert : l'appelant le DIT, car
  /// un appui qui ne produit rien doit s'expliquer, pas rester muet.
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
    case .jetonInvalide: return true
    // ET RIEN D'AUTRE, désormais. `.incomplete` portait AUSSI des messages sans
    // aucun rapport avec le jeton — « cette machine est hors ligne », ou une
    // action locale en échec —, si bien que la page reprochait son jeton à un Mac
    // éteint. Le remède proposé était alors faux, ce qui est pire que pas de
    // remède : on recopie un secret qui n'a rien à se reprocher.
    default: return false
    }
  }

  /// Le SERVICE a refusé le jeton — un `401`, et rien d'autre.
  ///
  /// POURQUOI CE N'EST PAS `jetonRefuse`. Les deux mènent au même endroit — le
  /// champ du jeton —, mais ils ne disent pas la même chose : un `401` accuse le
  /// SECRET (celui d'un autre hôte, par exemple), tandis qu'un jeton absent ou
  /// tronqué accuse la SAISIE. La page ne propose le rappel « chaque machine a le
  /// sien » que dans le premier cas : l'afficher pour un champ vide expliquerait
  /// un refus qui n'a pas eu lieu.
  public var jetonRefuseParLeService: Bool {
    if case .echec(.jetonRefuse) = connexion { return true }
    return false
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
      return "Le serveur joint ne voit aucune machine sur le tailnet (\(diagnosticServeurs)). Saisissez l'adresse ci-dessous."
    }
    return L("Le serveur joint ne voit aucune machine sur le tailnet. Saisissez l'adresse ci-dessous.")
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
    case let .jetonInvalide(detail): return .injoignable(detail)
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
    let jeton = jetonDeLaCible()
    guard !jeton.isEmpty else {
      connexion = .jetonInvalide("aucun jeton : collez-le d'abord")
      return
    }
    guard jeton.count == 43 else {
      connexion = .jetonInvalide("jeton incomplet : \(jeton.count) caractères au lieu de 43")
      return
    }
    do {
      let jonction = try await transport.joindre(adresse: adresse, jeton: jeton)
      self.client = jonction.client
      let depart = generationDuDepart()
      appliquerSessions(
        ListeSessions(protocole: 1, racine: nil, total: jonction.reponses,
          sessions: jonction.sessions, erreur: nil),
        vu: depart)
      connexion = .jointe(jonction.sante, reponses: jonction.reponses)
      // Le test d'adresse est aussi une connexion : si l'hôte sait publier la
      // liste des Macs, c'est le moment de la demander.
      if jonction.sante.capacites.decouverte == true { await chargerServeursDeLhote() }
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
    let (adresseAmorcee, jetonAmorce) = persistance.lireAmorcage()
    if let adresseAmorcee {
      viser(Cible(adresse: adresseAmorcee, nom: cible.nom))
    }
    if let jetonAmorce { jetonSaisi = jetonAmorce }
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
    guard !jetonSaisi.isEmpty else { return L("aucun") }
    return String(Empreinte.de(jetonSaisi).prefix(8))
  }

  /// Empreinte courte d'une chaîne — FNV-1a 64 bits, pas SHA-256 (voir
  /// `Empreinte.de`, qui dit pourquoi : ici on veut DISTINGUER deux secrets, pas
  /// résister à une attaque).

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
  public var jetonBienForme: Bool { ModeleApp.jetonBienForme(jetonSaisi) }

  /// La MÊME règle, en fonction pure d'une chaîne.
  ///
  /// POURQUOI ELLE EXISTE SÉPARÉMENT. La feuille « Adresse » juge le jeton
  /// qu'elle est en train de recevoir, AVANT de l'avoir confié au modèle : elle
  /// ne peut donc pas interroger `jetonSaisi`, qui décrit encore l'hôte
  /// précédent. Deux copies de cette règle auraient fini par diverger sur ce
  /// qu'est un jeton « complet » — et c'est la seule chose qui distingue une
  /// faute de collage d'un vrai refus du service.
  public nonisolated static func jetonBienForme(_ valeur: String) -> Bool {
    valeur.count == 43
      && valeur.allSatisfy { caractere in
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


  /// Colle le jeton depuis le presse-papier, POUR LA CIBLE.
  ///
  /// POURQUOI CE BOUTON. Le jeton fait 43 caractères en base64url, copié depuis
  /// un terminal : à la main, sur un clavier de téléphone, une saisie exacte
  /// est improbable. Le presse-papier supprime le risque de faute — et comme on
  /// nettoie les espaces, un retour à la ligne collé avec la valeur ne gêne pas.
  ///
  /// La feuille « Adresse » emploie cette forme : son adresse EST la cible, et
  /// elle engage le jeton plus tard (à la soumission).
  @discardableResult
  public func collerLeJeton() -> Bool {
    guard let nettoye = ModeleApp.jetonDuPressePapiers() else { return false }
    jetonSaisi = nettoye
    return true
  }

  /// Colle le jeton depuis le presse-papier POUR UNE MACHINE NOMMÉE.
  ///
  /// POURQUOI ELLE ENREGISTRE TOUT DE SUITE, contrairement à la précédente. Le
  /// champ d'une page de machine est celui d'un hôte CONNU : l'y coller est un
  /// geste délibéré, qui n'a pas à attendre une soumission, et c'est déjà le
  /// comportement de la frappe sur cette page.
  @discardableResult
  public func collerLeJeton(pour adresse: String) -> Bool {
    guard let nettoye = ModeleApp.jetonDuPressePapiers() else { return false }
    enregistrerJeton(nettoye, pour: adresse)
    return true
  }

  /// Le presse-papiers, nettoyé, s'il contient un jeton plausible.
  ///
  /// Rend `nil` — et l'appelant le DIT — quand il est vide ou trop court :
  /// « rien ne s'est passé » ne doit jamais être une réponse possible à un appui.
  nonisolated static func jetonDuPressePapiers() -> String? {
    let valeur: String?
    #if canImport(UIKit)
      valeur = UIPasteboard.general.string
    #elseif canImport(AppKit)
      valeur = NSPasteboard.general.string(forType: .string)
    #else
      valeur = nil
    #endif
    return jetonPlausible(valeur)
  }

  /// LA RÈGLE DE VALIDATION D'UN JETON COLLÉ, en un seul endroit.
  ///
  /// POURQUOI ELLE EST SÉPARÉE DE LA LECTURE. Sur iPhone, le collage passe
  /// désormais par le bouton système (`PasteButton`) : le texte n'est plus lu par
  /// nous, il arrive en paramètre. Deux chemins de collage — celui du système et
  /// celui du presse-papiers sur macOS — doivent appliquer LA MÊME règle : au
  /// moins 20 caractères, espaces de bord retirés. Deux copies auraient fini par
  /// diverger, et un jeton tronqué accepté d'un côté ne se diagnostique pas.
  nonisolated static func jetonPlausible(_ brut: String?) -> String? {
    guard let brut else { return nil }
    let nettoye = brut.trimmingCharacters(in: .whitespacesAndNewlines)
    guard nettoye.count >= 20 else { return nil }
    return nettoye
  }

  /// Adopte un jeton VENU DU SYSTÈME (bouton de collage), pour la saisie en cours.
  ///
  /// C'est le pendant de `collerLeJeton()` quand le texte est fourni par le
  /// bouton système plutôt que lu dans le presse-papiers.
  @discardableResult
  public func adopterJeton(_ brut: String) -> Bool {
    guard let nettoye = ModeleApp.jetonPlausible(brut) else {
      signaler(ModeleApp.messageJetonIllisible)
      return false
    }
    jetonSaisi = nettoye
    return true
  }

  /// Adopte un jeton venu du système POUR UNE MACHINE NOMMÉE, et l'enregistre.
  ///
  /// Même distinction que les deux `collerLeJeton` : le champ d'une page de
  /// machine appartient à un hôte CONNU, et l'y coller est un geste délibéré qui
  /// n'attend pas une soumission.
  @discardableResult
  public func adopterJeton(_ brut: String, pour adresse: String) -> Bool {
    guard let nettoye = ModeleApp.jetonPlausible(brut) else {
      signaler(ModeleApp.messageJetonIllisible)
      return false
    }
    enregistrerJeton(nettoye, pour: adresse)
    return true
  }

  /// CE QU'ON DIT QUAND LE COLLAGE NE DONNE RIEN D'EXPLOITABLE.
  ///
  /// Un presse-papiers vide est le cas le plus fréquent d'échec, et un appui qui
  /// ne produit RIEN est un mensonge d'interface. Le seuil est nommé parce qu'il
  /// est la seule chose vérifiable par l'utilisateur.
  static let messageJetonIllisible =
    "Rien à coller : le presse-papier est vide, ou ne contient pas un jeton exploitable (moins de 20 caractères)."

  // MARK: - Appairage (le QR du panneau web, scanné ou collé)

  /// LE NOM DE CET APPAREIL, tel qu'il sera proposé à l'hôte.
  ///
  /// POURQUOI IL EST ENVOYÉ, ET POURQUOI IL N'EST PAS CRU SUR PAROLE. Depuis que
  /// chaque appareil a SON jeton, la liste des appareils appairés sert à en
  /// révoquer un : sans nom, elle n'afficherait que des empreintes, et personne
  /// ne saurait lequel couper. L'hôte BORNE ce nom (longueur, caractères de
  /// commande, commandes bidi) parce qu'il vient du réseau — ici on se contente
  /// de proposer le meilleur nom disponible.
  ///
  /// SUR IOS 16 ET APRÈS, `UIDevice.current.name` rend un nom GÉNÉRIQUE
  /// (« iPhone ») tant que l'application n'a pas l'entitlement du nom d'appareil
  /// attribué par l'utilisateur. Ce n'est pas un défaut à réparer : c'est une
  /// limite d'iOS, et elle est écrite ici pour que personne ne cherche pourquoi
  /// tous les iPhone s'appellent « iPhone » dans la liste.
  public static var nomDeCetAppareil: String {
    #if canImport(UIKit)
      return UIDevice.current.name
    #elseif canImport(AppKit)
      return Host.current().localizedName ?? "Mac"
    #else
      return "appareil"
    #endif
  }

  /// APPAIRER PUIS SE CONNECTER — le geste complet, celui du scan et du collage.
  @discardableResult
  public func appairerEtConnecter(_ texte: String) async -> Bool {
    guard await appairer(texte) else { return false }
    await connecter()
    return true
  }

  /// APPAIRER — un jeton se POSE, un code s'ÉCHANGE.
  ///
  /// POURQUOI LES DEUX GENRES SONT ICI, ET PAS DANS LA VUE. Une vue qui
  /// enchaînerait « analyser », « échanger si c'est un code », « poser le jeton »
  /// et « se connecter » laisserait croire qu'un appairage appliqué mais non
  /// connecté est un état normal. Ce n'en est pas un : l'utilisateur a scanné
  /// pour se connecter.
  ///
  /// LE REFUS EST PARLANT, et il vient de l'analyse (sept motifs) ou de l'hôte
  /// (code expiré, déjà utilisé, hôte trop ancien). Jamais un « échec » nu : les
  /// causes ne se réparent pas pareil.
  @discardableResult
  public func appairer(_ texte: String) async -> Bool {
    switch Appairage.analyser(texte) {
    case .failure(let motif):
      signaler(motif.message)
      return false
    case .success(let charge):
      switch charge.genre {
      case .jeton:
        // LE JETON EST POSÉ TEL QUEL : c'est celui du terminal, ou celui d'une
        // version antérieure du panneau.
        return appliquer(hote: charge.hote, secret: charge.secret)
      case .code:
        return await echanger(charge)
      }
    }
  }

  /// ÉCHANGE UN CODE, PUIS POSE LE JETON REÇU.
  ///
  /// POURQUOI L'ÉCHANGE PASSE PAR LE TRANSPORT INJECTÉ, et pas par un appel
  /// direct : c'est ce qui rend le chemin éprouvable sans réseau, et c'est déjà
  /// la règle de tout le reste du modèle.
  private func echanger(_ charge: Appairage.Charge) async -> Bool {
    do {
      let appareil = try await transport.echangerAppairage(
        adresse: charge.adresse, code: charge.secret, nom: ModeleApp.nomDeCetAppareil)
      Trace.siActive(
        "[appairage] echange accepte vers \(charge.hote) : jeton de \(appareil.jeton.count) caracteres, portee \(appareil.portee ?? "inconnue")")
      return appliquer(hote: charge.hote, secret: appareil.jeton)
    } catch {
      // LE MESSAGE VIENT DU TYPE D'ERREUR, qui distingue un code expiré d'un hôte
      // trop ancien : deux causes, deux remèdes.
      signaler(String(describing: error))
      return false
    }
  }

  /// POSE L'ADRESSE ET LE JETON ENSEMBLE — dans cet ordre, et il est mesuré.
  ///
  /// `definirAdresse` RECHARGE le jeton gardé pour la nouvelle machine (chaque
  /// hôte a le sien). Engager le secret AVANT aurait donc été le remplacer par
  /// celui de l'ancienne cible.
  @discardableResult
  private func appliquer(hote: String, secret: String) -> Bool {
    definirAdresse("http://" + hote)
    enregistrerJeton(secret)
    Trace.siActive("[appairage] applique vers \(hote), jeton de \(secret.count) caracteres")
    return true
  }

  /// LE TEXTE D'APPAIRAGE DU PRESSE-PAPIERS, s'il y en a un.
  ///
  /// Rend `nil` quand le presse-papiers est vide — l'appelant le DIT, comme pour
  /// le jeton : « rien ne s'est passé » ne doit jamais être une réponse possible
  /// à un appui.
  nonisolated static func appairageDuPressePapiers() -> String? {
    let valeur: String?
    #if canImport(UIKit)
      valeur = UIPasteboard.general.string
    #elseif canImport(AppKit)
      valeur = NSPasteboard.general.string(forType: .string)
    #else
      valeur = nil
    #endif
    guard let brut = valeur else { return nil }
    let nettoye = brut.trimmingCharacters(in: .whitespacesAndNewlines)
    return nettoye.isEmpty ? nil : nettoye
  }

  /// Ce qu'on dit quand le presse-papiers ne contient pas d'appairage.
  static var messageAppairageIllisible: String {
    L("Rien à coller : le presse-papier est vide. Copiez le texte affiché sous le QR code du panneau « Appairer un appareil ».")
  }

  /// Colle ET appaire depuis le presse-papiers.
  @discardableResult
  public func collerAppairage() async -> Bool {
    guard let brut = ModeleApp.appairageDuPressePapiers() else {
      signaler(ModeleApp.messageAppairageIllisible)
      return false
    }
    return await appairer(brut)
  }

  /// CE QU'UNE RÉINITIALISATION A EFFECTIVEMENT EFFACÉ.
  ///
  /// POURQUOI UN COMPTE RENDU, ET PAS SEULEMENT UN EFFET. Un bouton qui ne dit pas
  /// ce qu'il a fait ne vaut pas mieux qu'un bouton sans effet : l'utilisateur ne
  /// peut pas savoir si ses jetons sont partis, ni si le fichier d'amorçage va
  /// tout ramener au lancement suivant. Ces trois nombres et ces deux drapeaux
  /// sont ce que l'écran affiche.
  public struct RapportDeReinitialisation: Equatable, Sendable {
    public let jetonsEffaces: Int
    public let clesOubliees: Int
    public let diagnosticEfface: Bool
    /// Un fichier d'amorçage est présent, et il N'A PAS été touché : il ré-amorcera
    /// l'application au lancement suivant. Le dire est le seul moyen de ne pas
    /// mentir sur ce que « réinitialiser » a fait.
    public let amorcageRestant: Bool
  }

  /// RÉINITIALISE L'APPLICATION SUR CET APPAREIL.
  ///
  /// CE QU'ELLE EFFACE : les jetons d'appareil du trousseau (TOUS, y compris ceux
  /// d'hôtes qu'on ne visite plus — voir `GardienDeJetons.effacerTout`), l'adresse
  /// et le nom mémorisés, les préférences par serveur, l'état de navigation, le
  /// réglage des alertes, et le fichier de diagnostic.
  ///
  /// CE QU'ELLE NE TOUCHE PAS, ET QUI EST DIT À L'ÉCRAN : le jeton du harness sur
  /// le Mac (il vit dans son coffre, pas ici), et le **fichier d'amorçage** déposé
  /// à la main — que l'application ne crée jamais, et qui la ré-amorcerait au
  /// lancement suivant.
  ///
  /// ELLE EST IRRÉVERSIBLE : un jeton effacé se retrouve en réappairant, pas en
  /// annulant. C'est pourquoi l'appelant demande confirmation AVANT.
  @discardableResult
  public func reinitialiser() async -> RapportDeReinitialisation {
    // L'AMORÇAGE EST LU AVANT TOUT : après le geste, la réponse doit décrire ce
    // qui RESTE, pas ce qui était là.
    let amorcage = persistance.amorcagePresent
    let jetons = gardien.effacerTout()
    let cles = persistance.toutOublier()
    let diagnostic = persistance.effacerDiagnostic()
    // LE MODÈLE REVIENT À L'ÉTAT D'UN APPAREIL NEUF. On réutilise `oublierServeur`
    // — une seule remise à zéro, celle qui est éprouvée — plutôt que d'en écrire
    // une seconde, qui oublierait forcément un champ.
    oublierServeur()
    // LES MIROIRS EN MÉMOIRE AUSSI — sans quoi la remise à zéro serait partielle
    // et se verrait plus tard. `toutOublier` a retiré les clés du disque, mais le
    // modèle garde encore ce qu'il avait LU : l'état de navigation (mode d'envoi,
    // session consultée, espaces dépliés) et les préférences par serveur. La
    // première écriture venue — un espace qu'on déplie, un mode qu'on change —
    // les remettrait sur le disque, et l'appareil « remis à zéro » retrouverait
    // les réglages d'avant.
    navigation = EtatDeNavigation()
    preferences = [:]
    alertesActives = false
    return RapportDeReinitialisation(
      jetonsEffaces: jetons, clesOubliees: cles, diagnosticEfface: diagnostic,
      amorcageRestant: amorcage)
  }

  /// Le texte du compte rendu — écrit ici pour que l'écran n'invente rien.
  public func texteDuRapport(_ rapport: RapportDeReinitialisation) -> String {
    var morceaux: [String] = []
    morceaux.append(
      rapport.jetonsEffaces == 0
        ? L("aucun jeton n'était gardé")
        : String(format: L("%d jeton(s) d'appareil effacé(s)"), rapport.jetonsEffaces))
    morceaux.append(
      rapport.clesOubliees == 0
        ? L("aucune préférence à oublier")
        : String(format: L("%d préférence(s) oubliée(s)"), rapport.clesOubliees))
    if rapport.diagnosticEfface { morceaux.append(L("diagnostic effacé")) }
    if rapport.amorcageRestant {
      morceaux.append(
        L(
          "le fichier d'amorçage est TOUJOURS LÀ : il ramènera l'adresse et le jeton au prochain lancement. Supprimez-le depuis le Mac si vous voulez une remise à zéro complète."
        ))
    }
    return morceaux.joined(separator: " · ")
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
    // Ce qui reste à relire est une MESURE locale — l'appareil porte-t-il une
    // adresse de tailnet, l'application est-elle installée —, et elle ne doit
    // rien au serveur qu'on vient d'oublier. On la refait donc, plutôt que de
    // garder un constat fait à un autre moment.
    relireEtatTailscale()
    sessions = []
    viderLeJournal()
    connexion = .inconnue
    persistance.oublierAdresse()
  }

  /// Le jeton saisi pour l'hôte VISÉ, gardé DÈS LA FRAPPE.
  ///
  /// POURQUOI PAS SEULEMENT À LA CONNEXION : on colle un jeton, on change d'avis
  /// ou de machine, et le secret serait perdu — alors qu'il vient d'être
  /// laborieusement recopié. Même raisonnement que l'adresse, mémorisée dès la
  /// frappe. Le jeton, lui, ne va JAMAIS dans les préférences : il va là où un
  /// secret doit vivre (voir `enregistrerJeton`).
  public func definirJeton(_ valeur: String) {
    enregistrerJeton(valeur)
  }

  /// Le même geste, POUR UNE MACHINE NOMMÉE.
  ///
  /// POURQUOI L'ADRESSE EST UN PARAMÈTRE. La page d'une machine peut être celle
  /// d'un AUTRE hôte que la cible — on ouvre la fiche d'un Mac sans s'y
  /// connecter. Or la lecture, l'écriture et l'effacement du jeton visaient tous
  /// `cible.adresse` : le champ annonçait « jeton de cet hôte » et agissait sur
  /// un autre. Un jeton collé là partait vers la mauvaise machine, et celui
  /// d'une autre s'affichait sous ce nom-là.
  public func definirJeton(_ valeur: String, pour adresse: String) {
    enregistrerJeton(valeur, pour: adresse)
  }

  /// Efface le jeton de L'HÔTE VISÉ : en mémoire, et là où il était gardé.
  public func effacerJeton() {
    effacerJeton(pour: cible.adresse)
  }

  /// Efface le jeton d'une machine nommée.
  public func effacerJeton(pour adresse: String) {
    let cle = IdentiteHote.cle(adresse)
    // Le champ en mémoire ne décrit que la cible : l'effacer parce qu'on efface
    // le jeton d'une AUTRE machine ferait disparaître sous les yeux de
    // l'utilisateur un secret qui n'était pas visé.
    if cle == IdentiteHote.cle(cible.adresse) { jetonSaisi = "" }
    gardien.effacer(pour: cle)
  }

  /// Enregistre le jeton saisi : au trousseau sur iOS, en mémoire sur macOS.
  ///
  /// N'est appelé qu'à la SOUMISSION du formulaire, jamais à la frappe : un
  /// enregistrement par caractère persistait un jeton tronqué, et faisait
  /// croire à un jeton disponible alors que la saisie n'était pas terminée.
  public func enregistrerJeton(_ valeur: String) {
    enregistrerJeton(valeur, pour: cible.adresse)
  }

  /// Enregistre le jeton D'UNE MACHINE NOMMÉE.
  public func enregistrerJeton(_ valeur: String, pour adresse: String) {
    let propre = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    let cle = IdentiteHote.cle(adresse)
    // LE CHAMP EN MÉMOIRE NE DÉCRIT QUE LA CIBLE. Y écrire le jeton d'une autre
    // machine ferait afficher ici le secret collé là-bas — et, pire, pourrait
    // l'envoyer à la cible.
    if cle == IdentiteHote.cle(cible.adresse) {
      jetonSaisi = propre
      cleJetonChargee = cle
    }

    // LE JETON DE L'HÔTE LOCAL N'EST PAS RECOPIÉ ICI. Il est dans le coffre du
    // harness, qui est sa source ; en garder une seconde copie multiplierait les
    // endroits où un secret peut fuir sans rien apporter.
    guard !adresse.isEmpty, !estHoteLocal(adresse) else { return }

    // C'est le GARDIEN qui sait s'il peut garder durablement — le modèle n'a pas
    // à connaître la plateforme (il le faisait, et c'était une erreur de
    // conception : deux `#if` dans la logique métier, pour une question de
    // stockage).
    if propre.isEmpty {
      gardien.effacer(pour: cle)
    } else {
      gardien.ecrire(propre, pour: cle)
    }
  }

  /// LE JETON D'UNE MACHINE NOMMÉE — ce que son champ doit afficher.
  ///
  /// POURQUOI ELLE PREND L'ADRESSE. `jetonSaisi` ne décrit QUE la cible : il est
  /// sa valeur la plus fraîche (un collage qui n'est pas encore enregistré, une
  /// amorce de fichier), et il n'a rien à dire d'une autre machine. Le lire pour
  /// toutes les pages faisait afficher le jeton d'une machine sous le nom d'une
  /// autre.
  public func jeton(pour adresse: String) -> String {
    let cle = IdentiteHote.cle(adresse)
    if cle == IdentiteHote.cle(cible.adresse), !jetonSaisi.isEmpty { return jetonSaisi }
    if let garde = gardien.lire(pour: cle), !garde.isEmpty { return garde }
    guard estHoteLocal(adresse) else { return "" }
    return CoffreDuHarness.jetonDeLaMachine() ?? ""
  }

  /// Vrai si un jeton est disponible POUR CETTE MACHINE, sans le révéler.
  public func jetonDisponible(pour adresse: String) -> Bool { !jeton(pour: adresse).isEmpty }

  /// Longueur du jeton de CETTE machine. Jamais le jeton lui-même.
  public func longueurJeton(pour adresse: String) -> Int { jeton(pour: adresse).count }

  /// La forme du jeton de CETTE machine.
  public func jetonBienForme(pour adresse: String) -> Bool {
    ModeleApp.jetonBienForme(jeton(pour: adresse))
  }

  /// LE COFFRE DE CETTE MACHINE PROPOSE-T-IL UN AUTRE JETON QUE LE CHAMP ?
  ///
  /// POURQUOI. Mesure du 13 septembre : une instance de l'application présentait
  /// un jeton de 43 caractères que le service refusait (`401`), alors que le
  /// coffre de la machine contenait le bon — l'application restait donc bloquée
  /// sur un secret étranger, sans rien pour en sortir qu'un recollage manuel.
  ///
  /// La comparaison se fait PAR EMPREINTE, jamais par valeur : on veut seulement
  /// savoir si les deux diffèrent, et c'est exactement ce pour quoi `Empreinte`
  /// existe (le jeton n'est ni affiché, ni journalisé, ni recopié ailleurs).
  public func jetonDuCoffreDiffert(pour adresse: String) -> Bool {
    guard estHoteLocal(adresse),
      let duCoffre = CoffreDuHarness.jetonDeLaMachine(), !duCoffre.isEmpty
    else { return false }
    return !ModeleApp.memeJeton(duCoffre, jeton(pour: adresse))
  }

  /// Adopte le jeton du coffre pour cette machine — sans jamais le montrer.
  ///
  /// N'est proposé que là où le coffre fait autorité : la machine locale, celle
  /// qui exécute le harness. Le coffre d'un AUTRE Mac n'est pas lisible d'ici, et
  /// prétendre le contraire serait une devinette.
  public func adopterLeJetonDuCoffre(pour adresse: String) {
    guard estHoteLocal(adresse), let duCoffre = CoffreDuHarness.jetonDeLaMachine(),
      !duCoffre.isEmpty
    else { return }
    enregistrerJeton(duCoffre, pour: adresse)
  }

  /// Deux jetons sont-ils le MÊME, sans les révéler ?
  ///
  /// Fonction pure, pour que la règle qui décide d'afficher « essayer le jeton du
  /// coffre » soit éprouvable sans coffre, sans réseau et sans secret.
  public nonisolated static func memeJeton(_ gauche: String, _ droite: String) -> Bool {
    guard !gauche.isEmpty, !droite.isEmpty else { return false }
    return Empreinte.de(gauche) == Empreinte.de(droite)
  }

  /// CETTE ADRESSE EST-ELLE CELLE DE LA MACHINE QUI HÉBERGE LE HARNESS ?
  ///
  /// DEUX CHEMINS, ET LES DEUX EXISTENT. Sur iOS, la liste vient d'un hôte, qui
  /// CETTE APPLICATION — jamais « l'hôte qui a répondu ». Sur macOS, la découverte est
  /// LOCALE et laisse ce champ faux pour tout le monde : la machine locale s'y
  /// reconnaît par son adresse — le harness n'écoute que sur la boucle locale.
  func estHoteLocal(_ adresse: String) -> Bool {
    // DEUX FAITS LOCAUX, ET RIEN D'AUTRE : la boucle locale, et les adresses que
    // la découverte locale a marquées comme étant celles de CET appareil. Le
    // marqueur `estLocal` d'une liste REÇUE n'est pas consulté — c'est lui qui a
    // fait envoyer le jeton du coffre local à un Mac distant.
    let cle = IdentiteHote.cle(adresse)
    if !cle.isEmpty, adressesDeCetAppareil.contains(cle) { return true }
    return ModeleApp.estBoucleLocale(adresse)
  }

  /// `127.0.0.1`, `localhost`, `::1` — la boucle locale, et rien d'autre.
  nonisolated static func estBoucleLocale(_ adresse: String) -> Bool {
    guard let brut = ExceptionATS.hote(adresse)?.lowercased() else { return false }
    // `URLComponents` rend l'hôte IPv6 tantôt entre crochets, tantôt nu selon la
    // forme de l'adresse : les deux se ramènent à la même chose.
    let hote = brut.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    return hote == "localhost" || hote == "127.0.0.1" || hote == "::1"
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
    "« \(serveur.nom) » est hors ligne sur le tailnet. Allumez-le, ou choisissez une machine en ligne : la liste se rafraîchit toute seule."
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
    let jeton = jetonDeLaCible()
    guard !jeton.isEmpty else {
      connexion = .jetonInvalide(
        "Aucun jeton d'appareil. Récupérez-le dans la sortie du harness sur l'hôte, au premier chargement du plugin.")
      return
    }
    // Un jeton tronqué enverrait une requête vouée au 401, en accusant le
    // serveur à tort : on le dit avant, avec le compte exact.
    guard jeton.count == 43 else {
      connexion = .jetonInvalide("jeton incomplet : \(jeton.count) caractères au lieu de 43. Recopiez-le en entier.")
      return
    }
    // TRACE TEMPORAIRE : ou passe le temps au demarrage.
    let debutConnexion = Date()
    let adresseVisee = adresse
    // Le jeton n'est confié au trousseau qu'ici, une fois la saisie terminée.
    enregistrerJeton(jeton)
    await executer {
      // DEUX DÉLAIS POUR DEUX QUESTIONS, et l'ordre qui va avec : la brève
      // d'abord. C'est la politique de `Connexion`, éprouvée là-bas.
      let jonction = try await self.transport.joindre(adresse: self.adresse, jeton: jeton)
      self.client = jonction.client
      let depart = self.generationDuDepart()
      self.appliquerSessions(
        ListeSessions(protocole: 1, racine: nil, total: jonction.reponses,
          sessions: jonction.sessions, erreur: nil),
        vu: depart)
      // LE serveur a répondu ET accepté le jeton : une seule valeur le dit —
      // capacités, nombre de sessions rendues, et « joint » en découlent.
      self.connexion = .jointe(jonction.sante, reponses: jonction.reponses)
    }
    Trace.siActive("[demarrage] connecter \(adresseVisee) : \(Int(Date().timeIntervalSince(debutConnexion) * 1000)) ms, erreur=\(erreur == nil ? "non" : "OUI")")
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
      let depart = self.generationDuDepart()
      let liste = try await client.listerSessions(limite: 200)
      self.appliquerSessions(liste, vu: depart)
    }
    if erreur == nil { demarrerSuivi() }
  }

  public func ouvrir(_ session: SessionListee) async {
    // Ouvrir, c'est voir : le rappel de fin de cette session n'a plus lieu d'être.
    marquerCommeVue(session.id)
    guard let client else { return }
    // ── ON VIDE AVANT DE DEMANDER, ET C'EST LA CORRECTION ────────────────────
    //
    // Un échec de lecture laissait l'ANCIEN journal sous le titre de la NOUVELLE
    // session : ni contenu juste, ni chargement, ni erreur. Le voile de
    // chargement, lui, était conditionné à `journal.isEmpty` — donc jamais montré
    // quand un ancien journal traînait. Vider d'abord rend les trois états
    // possibles et distincts : on lit, on a lu, on a échoué.
    journal = []
    journalPour = session.id
    sessionOuverte = nil
    erreurJournal = nil
    journalEnLecture = session.id
    defer {
      if journalEnLecture == session.id { journalEnLecture = nil }
    }
    let depart = generationDuDepart()
    await executer {
      do {
        let journal = try await client.lireSession(
          session.id,
          demande: DemandeJournal(depuis: 0, limite: 400))
        // Le journal vient d'UN serveur ET d'UNE session : si l'un ou l'autre a
        // changé pendant la lecture, ces événements décrivent autre chose.
        self.appliquerJournal(
          journal.enregistrements.map(DecodeurEvenement.afficher), de: session.id, vu: depart)
        self.sessionOuverte = journal.session
      } catch {
        // L'ÉCHEC EST CONSIGNÉ POUR CETTE SESSION, et il est NOMMÉ à l'écran : la
        // connexion peut très bien aller bien — c'est la lecture de CE journal
        // qui a échoué, et le dire évite de chercher une panne réseau.
        self.consignerEchecJournal(error, pour: session.id)
      }
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

  /// LES BROUILLONS, PAR COUPLE HÔTE/SESSION — jamais un seul champ.
  ///
  /// POURQUOI CE N'EST PLUS UN CHAMP UNIQUE. Le texte en cours était commun à
  /// TOUTES les sessions : changer de session le conservait, et il pouvait donc
  /// partir vers une AUTRE — un message écrit pour l'une atterrissait dans
  /// l'autre, sans que rien ne le signale. La clé est le couple hôte/session,
  /// comme celle du jeton : c'est ce qui rend vrai ce que l'écran montre, un
  /// champ qui appartient à UNE session d'UN hôte.
  ///
  /// Un brouillon n'est PAS un secret : il vit en mémoire, et il disparaît à la
  /// fermeture de l'application. Le garder d'une exécution à l'autre demanderait
  /// d'écrire dans les préférences ce que l'utilisateur n'a pas encore envoyé —
  /// une décision qui n'appartient pas à ce correctif.
  private var brouillons: [String: String] = [:]
  /// Un envoi est en vol : le bouton se verrouille, la frappe continue.
  public private(set) var envoiEnCours = false
  /// Acquittement du dernier envoi réussi, **et la session qu'il concerne**.
  ///
  /// POURQUOI LA SESSION EST GARDÉE AVEC LE MESSAGE. Un envoi peut être acquitté
  /// APRÈS qu'on a changé de session : le message s'afficherait alors sous une
  /// session qui n'a rien envoyé. Le couple (session, texte) rend ce mensonge
  /// impossible — la vue ne lit que ce qui concerne SA session.
  private var acquittement: (session: String, texte: String)?
  /// Motif du dernier refus, en français, et la session qui l'a reçu.
  private var refus: (session: String, texte: String)?

  /// Le brouillon d'UNE session. Vide pour une session sans texte en cours.
  public func brouillon(pour identifiant: String) -> String {
    brouillons[cleBrouillon(pour: identifiant)] ?? ""
  }

  /// Écrit le brouillon d'UNE session — la frappe ne touche aucune autre.
  public func definirBrouillon(_ texte: String, pour identifiant: String) {
    brouillons[cleBrouillon(pour: identifiant)] = texte
  }

  /// Le brouillon de cette session est-il vide, aux blancs près ?
  ///
  /// Sert au bouton d'envoi : il se verrouille sur du vide, et « vide » veut
  /// dire « rien qui puisse partir », pas « zéro caractère ».
  public func brouillonVide(pour identifiant: String) -> Bool {
    brouillon(pour: identifiant).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// L'acquittement de CETTE session, s'il y en a un à montrer.
  public func acquittement(pour identifiant: String) -> String? {
    acquittement?.session == identifiant ? acquittement?.texte : nil
  }

  /// Le refus de CETTE session, s'il y en a un à montrer.
  public func refusEcriture(pour identifiant: String) -> String? {
    refus?.session == identifiant ? refus?.texte : nil
  }

  /// La clé d'un brouillon : l'hôte ET la session, comme pour le jeton.
  private func cleBrouillon(pour identifiant: String) -> String {
    "\(IdentiteHote.cle(adresse))|\(identifiant)"
  }

  /// RETIRE DU BROUILLON CE QUI VIENT D'ÊTRE ACQUITTÉ — et rien de plus.
  ///
  /// POURQUOI CE N'EST PAS « brouillon = "" ». Le champ reste modifiable pendant
  /// l'envoi (le modèle le dit lui-même : « la frappe continue ») : effacer après
  /// l'attente réseau détruisait donc la frappe concurrente — exactement ce que
  /// l'utilisateur venait d'écrire pendant que son message partait.
  ///
  /// Trois cas, et le troisième est le plus important :
  ///
  ///   - le brouillon est encore EXACTEMENT ce qui est parti : il est vidé ;
  ///   - il COMMENCE par ce qui est parti : seul ce préfixe est retiré, la suite
  ///     reste sous les doigts ;
  ///   - il a divergé : on ne touche à RIEN. Deviner quoi garder reviendrait à
  ///     effacer un texte que personne n'a envoyé.
  func retirerCeQuiEstAcquitte(_ texteEnvoye: String, pour identifiant: String) {
    let courant = brouillon(pour: identifiant)
    if courant.trimmingCharacters(in: .whitespacesAndNewlines) == texteEnvoye {
      brouillons[cleBrouillon(pour: identifiant)] = ""
      return
    }
    guard courant.hasPrefix(texteEnvoye) else { return }
    brouillons[cleBrouillon(pour: identifiant)] =
      String(courant.dropFirst(texteEnvoye.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

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

  /// POURQUOI CETTE MACHINE NE PEUT PAS ÉCRIRE — la question que l'écran doit
  /// RÉPONDRE, et non seulement constater.
  ///
  /// POURQUOI CE TEXTE EXISTE. Le composeur disparaissait en silence quand l'hôte
  /// n'annonçait pas l'écriture : l'écran avait l'air complet, et rien ne disait
  /// que répondre était impossible — ni pourquoi. Or les causes ont des remèdes
  /// qui ne sont PAS au même endroit :
  ///
  ///   - le jeton est en **lecture seule** : le remède est sur la machine qui
  ///     héberge le harness (`DSH_REMOTE_PORTEE=ecriture`), pas ici ;
  ///   - l'hôte **ne monte pas** le service d'écriture : c'est sa composition, et
  ///     aucune action de l'application n'y changera rien ;
  ///   - rien n'est **joint** : il n'y a rien à expliquer encore.
  ///
  /// `portee` est optionnelle, et c'est le point délicat : un hôte antérieur à la
  /// portée ne la publie pas, et `nil` doit se lire « ne sait pas » — l'annoncer
  /// comme « lecture seule » serait une affirmation inventée.
  public var raisonSansEcriture: String? {
    ModeleApp.raisonSansEcriture(capacites: capacites, portee: santeJointe?.portee)
  }

  /// Version PURE — éprouvable sans réseau, sans connexion et sans attente.
  ///
  /// `nonisolated` À DESSEIN, comme les autres décisions de ce modèle : elle ne
  /// touche aucun état, donc un test l'interroge directement.
  nonisolated static func raisonSansEcriture(capacites: Sante.Capacites?, portee: String?) -> String? {
    // Rien n'est joint : il n'y a rien à expliquer encore, et dire « cet hôte
    // n'annonce pas l'écriture » serait parler d'un hôte qu'on n'a pas joint.
    guard let capacites else { return nil }
    guard !capacites.ecriture else { return nil }
    if portee == "lecture" {
      return
        "Ce jeton lit sans écrire : l'écriture demande un jeton de portée « ecriture », tiré par un harness relancé avec DSH_REMOTE_PORTEE=ecriture."
    }
    // La portée n'est pas dite, ou l'hôte ne monte pas le service : dans les deux
    // cas, l'action est du côté de l'hôte, et on ne l'invente pas.
    return
      "Cet hôte n'annonce pas l'écriture : cette composition ne monte pas le service qui permet d'envoyer un message."
  }

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
    let texte = brouillon(pour: session.id).trimmingCharacters(in: .whitespacesAndNewlines)
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
      // CE QUI EST RETIRÉ EST CE QUI EST PARTI, pas ce que le champ contient
      // maintenant : la frappe concurrente survit à l'acquittement.
      retirerCeQuiEstAcquitte(texte, pour: session.id)
      refus = nil
      acquittement = (
        session: session.id,
        texte: reponse.reprise == true
          ? "accepté — la session était fermée, l'hôte l'a reprise"
          : "accepté — la réponse arrivera dans le journal"
      )
    } catch {
      // Le texte ET l'identifiant restent : rejouer ne créera pas de doublon.
      refus = (session: session.id, texte: Self.expliquerEcriture(error))
      acquittement = nil
    }
  }

  /// Interrompt le tour en cours. La file d'attente est conservée.
  public func annulerTour(_ session: SessionListee) async {
    guard let client else { return }
    do {
      let reponse = try await client.annuler(session.id)
      acquittement = reponse.annule ? (session: session.id, texte: "tour interrompu") : nil
      refus = reponse.annule ? nil : (session: session.id, texte: "l'hôte n'a pas interrompu le tour")
    } catch {
      refus = (session: session.id, texte: Self.expliquerEcriture(error))
      acquittement = nil
    }
  }

  /// Efface les messages d'état du composeur (acquittement ou refus).
  ///
  /// NE TOUCHE PAS AUX BROUILLONS, et c'est une correction : cette fonction est
  /// appelée au changement de session, et elle effaçait autrefois le texte en
  /// cours — c'est-à-dire le travail de l'utilisateur. Chaque session garde
  /// désormais le sien (`brouillon(pour:)`), et seuls les MESSAGES sont oubliés :
  /// un acquittement affiché sous une autre session ferait croire qu'elle le
  /// concerne.
  public func oublierEtatEcriture() {
    acquittement = nil
    refus = nil
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
    viderLeJournal()
  }

  /// Le journal ET ce qui le rattache à sa session.
  ///
  /// UN SEUL ENDROIT, parce que l'oubli d'un des trois champs donne exactement le
  /// défaut qu'on répare : un journal affiché sous le nom d'une autre session.
  private func viderLeJournal() {
    journal = []
    sessionOuverte = nil
    journalPour = nil
    erreurJournal = nil
    journalEnLecture = nil
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

  /// LE SERVEUR DONT ON MONTRE LES ESPACES DE TRAVAIL — son nom, jamais deviné.
  ///
  /// POURQUOI IL EXISTE. Les espaces listés ne sont pas un ensemble global : ce
  /// sont ceux du serveur JOINT, et ils changent quand on change de machine. Or
  /// le nom de ce serveur n'est visible nulle part quand une session est ouverte
  /// — la vignette du carrousel n'affiche que le premier mot du nom, et deux
  /// Macs peuvent le partager (« Portable Un », « Portable Deux »). L'en-tête de
  /// la section le dit donc, à l'endroit où le lecteur se pose la question.
  ///
  /// `nil` quand il n'y a RIEN à attribuer : une liste vide n'appartient à
  /// personne, et nommer un serveur au-dessus de rien laisserait croire qu'il a
  /// répondu.
  public var nomDuServeurAffiche: String? {
    guard !sessions.isEmpty || !espacesHote.isEmpty else { return nil }
    if let nom = serveurChoisi?.nom, !nom.isEmpty { return nom }
    if let nom = nomServeur, !nom.isEmpty { return nom }
    // Adresse saisie à la main, machine inconnue de la liste : on dit l'hôte,
    // qui est un fait, plutôt que rien.
    return ExceptionATS.hote(adresse)
  }

  /// Sessions regroupées par espace de travail, comme dans l'interface web.
  public var espaces: [EspaceDeTravail] {
    Regroupement.espaces(sessionsFiltrees, hotes: espacesHote)
  }

  /// L'ÉTAT D'UNE SESSION, tel que la liste l'affiche — une seule règle.
  public func etatDe(_ session: SessionListee) -> EtatSession {
    EtatSession.de(session, rappelDeFin: aTermine(session.id))
  }

  /// LES SESSIONS QUI DEMANDENT QUELQUE CHOSE, en tête de liste.
  ///
  /// POURQUOI CETTE LISTE EXISTE. C'était l'information la plus actionnable de
  /// l'application, et elle était ENTERRÉE : il fallait déplier dix espaces et
  /// lire des pastilles de huit points pour trouver la session bloquée sur une
  /// question. Une liste qui trie par urgence vaut mieux qu'une liste qui trie
  /// par date quand la question est « qui m'attend ».
  ///
  /// L'ORDRE EST CELUI DE L'URGENCE, et il suit celui d'`EtatSession` : une
  /// session qui ATTEND UNE DÉCISION passe avant une fin de tour non lue — l'une
  /// est bloquée sur vous, l'autre vous informe. À urgence égale, la plus récente
  /// d'abord.
  public var sessionsQuiAttendent: [SessionListee] {
    let retenues = sessionsFiltrees.compactMap { session -> (SessionListee, EtatSession)? in
      let etat = etatDe(session)
      guard etat == .attendReponse || etat == .terminee else { return nil }
      return (session, etat)
    }
    return
      retenues
      .sorted { gauche, droite in
        if gauche.1 != droite.1 { return gauche.1 == .attendReponse }
        let dateGauche = gauche.0.resume.dernierEvenementLe ?? 0
        let dateDroite = droite.0.resume.dernierEvenementLe ?? 0
        return dateGauche > dateDroite
      }
      .map(\.0)
  }

  /// Le résumé d'un espace : son total, et ce qui y attend une action.
  public func resume(_ espace: EspaceDeTravail) -> ResumeEspace {
    Regroupement.resume(espace.sessions, terminees: terminees)
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
    guard hoteEstJoint else { return }
    guard let liste = try? await transport.espacesDeLhote(adresse: adresse, jeton: jetonDeLaCible())
    else { return }
    appliquerEspaces(liste, vu: generationDuDepart())
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

  /// Consigne la dernière erreur — le fichier, sa raison d'être et ce qu'il ne
  /// contient JAMAIS sont documentés dans `Persistance.consignerDiagnostic`.
  private func journaliserDiagnostic(adresse: String, message: String) {
    persistance.consignerDiagnostic(
      adresse: adresse, message: message,
      empreinteJeton: empreinteJeton, longueurJeton: longueurJeton)
  }
}

