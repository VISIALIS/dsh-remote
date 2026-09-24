import Foundation

/// Un espace de travail et les sessions qu'il contient.
///
/// Reproduit l'arbre de l'interface web : un dossier par espace de travail, ses
/// sessions dessous, et les sous-agents imbriqués sous leur session parente.
public struct EspaceDeTravail: Sendable, Identifiable, Hashable {
  /// Identifiant du registre de l'hôte, ou le chemin quand l'espace est déduit.
  public let id: String
  /// Nom affiché — le titre du registre, ou le dernier segment du chemin.
  public let nom: String
  /// Chemin complet, pour lever toute ambiguïté entre deux dossiers homonymes.
  public let chemin: String
  public let sessions: [SessionListee]
  /// Vrai quand l'espace est ENREGISTRÉ mais n'a aucune session.
  ///
  /// C'est un état que l'interface web montre (un dossier choisi, pas encore
  /// utilisé) et que l'application ne pouvait pas représenter tant qu'elle
  /// déduisait ses espaces des sessions.
  public let sansSession: Bool
  /// Vrai pour le regroupement des sessions qui n'appartiennent à aucun espace :
  /// le « Ungrouped » de l'interface web, toujours affiché en dernier.
  public let horsEspaces: Bool

  public var nbSessions: Int { sessions.count }
  public var nbVivantes: Int { sessions.filter { $0.vivante == true }.count }
}

/// CE QU'UN ESPACE DEMANDE, EN UNE LIGNE COURTE.
///
/// POURQUOI CE RÉSUMÉ EXISTE. L'en-tête d'un espace replié n'affichait que son
/// nombre de sessions : replier un dossier cachait donc l'information la plus
/// actionnable — celle d'une session qui attend une réponse. Ce qui compte à
/// l'état replié se voit maintenant sans déplier.
public struct ResumeEspace: Equatable, Sendable {
  public let total: Int
  public let enAttente: Int
  public let terminees: Int

  public init(total: Int, enAttente: Int, terminees: Int) {
    self.total = total
    self.enAttente = enAttente
    self.terminees = terminees
  }

  /// « 6 · 1 en attente » — le total, puis ce qui appelle une action.
  ///
  /// Le nombre seul reste quand rien n'attend : c'est le cas le plus fréquent, et
  /// une ligne d'en-tête chargée se lit moins vite.
  public var texte: String {
    var morceaux = ["\(total)"]
    if enAttente > 0 { morceaux.append("\(enAttente) en attente") }
    if terminees > 0 { morceaux.append("\(terminees) terminée\(terminees > 1 ? "s" : "")") }
    return morceaux.joined(separator: " · ")
  }
}

/// Regroupe des sessions en espaces de travail.
///
/// POURQUOI UN REGROUPEMENT PLUTÔT QU'UN TRI. Une liste plate de 106 sessions
/// mêlant dix projets est illisible : on ne cherche pas « une session », on
/// cherche « la session de ce projet ». L'interface web le fait déjà ; s'en
/// écarter ferait deux outils qui ne se ressemblent plus.
public enum Regroupement {
  /// Nom d'espace de travail d'une session.
  ///
  /// On préfère `cwd`, qui vient du journal et est exact. Le nom du dossier de
  /// projet ne sert que de repli : DSH y remplace les `/` par des `-`, ce qui
  /// rend « dsh-plugins » indiscernable de « dsh/plugins ». Un libellé déduit
  /// d'un encodage perdant ne doit jamais primer sur une valeur exacte.
  public static func nomEspace(_ session: SessionListee) -> (nom: String, chemin: String) {
    if let cwd = session.resume.cwd, !cwd.isEmpty {
      let nom = (cwd as NSString).lastPathComponent
      return (nom.isEmpty ? cwd : nom, cwd)
    }
    if let indicatif = session.cwdIndicatif, !indicatif.isEmpty {
      let nom = (indicatif as NSString).lastPathComponent
      return (nom.isEmpty ? indicatif : nom, indicatif)
    }
    return ("Sans projet", "?")
  }

  /// Vrai si la session est un sous-agent délégué.
  ///
  /// `profondeurDelegation` vient de l'en-tête du journal ; une session de
  /// profondeur supérieure à zéro a été créée par une autre.
  public static func estSousAgent(_ session: SessionListee) -> Bool {
    (session.resume.profondeurDelegation ?? 0) > 0
  }

  /// CE QU'UN ENSEMBLE DE SESSIONS DEMANDE — total, en attente, terminées.
  ///
  /// POURQUOI ELLE EST ICI. Le compte s'appuie sur `EtatSession.de`, la règle
  /// unique de l'état d'une session listée : la même que la pastille, la même que
  /// le tri d'urgence. Un compteur qui compterait autrement que ce que la liste
  /// montre serait un second vocabulaire pour un seul fait.
  public static func resume(
    _ sessions: [SessionListee], terminees: Set<String> = []
  ) -> ResumeEspace {
    var enAttente = 0
    var finies = 0
    for session in sessions {
      switch EtatSession.de(session, rappelDeFin: terminees.contains(session.id)) {
      case .attendReponse: enAttente += 1
      case .terminee: finies += 1
      default: break
      }
    }
    return ResumeEspace(total: sessions.count, enAttente: enAttente, terminees: finies)
  }

  /// Construit l'arbre : espaces de travail triés, sessions récentes d'abord.
  ///
  /// DEUX SOURCES, ET LA SECONDE EST UN REPLI. Quand l'hôte publie ses espaces
  /// (`/v1/espaces`), c'est LUI qui fait foi : il connaît les espaces **sans
  /// session**, et l'appartenance d'une session y est un fait du registre — pas
  /// une comparaison de chemins, qui se tromperait sur un dossier renommé, deux
  /// projets homonymes ou un sous-agent. Sans cette source (hôte plus ancien,
  /// ou route indisponible), on retombe sur le regroupement par `cwd`, qui est
  /// ce que faisait l'application avant.
  public static func espaces(_ sessions: [SessionListee], hotes: [EspaceHote] = []) -> [EspaceDeTravail] {
    guard !hotes.isEmpty else { return espacesDeduits(sessions) }
    return espacesDeclares(sessions, hotes: hotes)
  }

  /// Arbre construit sur le REGISTRE de l'hôte.
  ///
  /// L'ordre des espaces est celui du registre — création décroissante — et il
  /// est conservé tel quel : retrier ici ferait diverger l'application du web à
  /// la première évolution de la règle.
  private static func espacesDeclares(_ sessions: [SessionListee], hotes: [EspaceHote]) -> [EspaceDeTravail] {
    let parIdentifiant = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { premier, _ in premier })
    var attribuees: Set<String> = []
    var espaces: [EspaceDeTravail] = []

    for hote in hotes {
      let membres = hote.sessions.compactMap { identifiant -> SessionListee? in
        guard let session = parIdentifiant[identifiant] else { return nil }
        attribuees.insert(identifiant)
        return session
      }
      espaces.append(
        EspaceDeTravail(
          id: hote.id,
          nom: nomAffiche(titre: hote.titre, chemin: hote.chemin),
          chemin: hote.chemin,
          sessions: ordonner(membres),
          // VIDE AU SENS DU REGISTRE, et non « rien à afficher ici » : une
          // recherche qui ne retient aucune session d'un espace ne rend pas cet
          // espace vide pour autant. Confondre les deux ferait clignoter
          // l'icône pendant une recherche.
          sansSession: hote.sessions.isEmpty,
          horsEspaces: false))
    }

    // Ce qui reste n'appartient à aucun espace : le « Ungrouped » du web, en
    // dernier — et seulement s'il y a quelque chose à montrer.
    let orphelines = sessions.filter { !attribuees.contains($0.id) }
    if !orphelines.isEmpty {
      espaces.append(
        EspaceDeTravail(
          id: "sans-espace",
          nom: "Sans espace",
          chemin: "",
          sessions: ordonner(orphelines),
          sansSession: false,
          horsEspaces: true))
    }
    return espaces
  }

  /// Titre d'un espace : celui du registre, sinon le nom du dossier.
  ///
  /// Un titre vide ne doit jamais produire une ligne sans libellé.
  static func nomAffiche(titre: String, chemin: String) -> String {
    let propre = titre.trimmingCharacters(in: .whitespacesAndNewlines)
    if !propre.isEmpty { return propre }
    let segment = (chemin as NSString).lastPathComponent
    return segment.isEmpty ? chemin : segment
  }

  /// Sessions d'un espace : les plus récentes d'abord.
  ///
  /// C'est le tri par ACTIVITÉ, celui que l'interface web applique à l'intérieur
  /// d'un espace — l'ordre des espaces, lui, suit la création.
  ///
  /// La LIGNÉE n'entre pas dans l'ordre : un sous-agent se classe par son
  /// activité comme les autres sessions, et c'est le RENDU qui l'indente. Trier
  /// « les racines puis les enfants » ferait dépendre la position d'une session
  /// de sa parenté — l'interface web ne le fait pas non plus (« build one group
  /// without projecting session lineage into presentation »).
  static func ordonner(_ sessions: [SessionListee]) -> [SessionListee] {
    sessions.sorted { dateActivite($0) > dateActivite($1) }
  }

  /// Arbre DÉDUIT des sessions, par `cwd` — le repli.
  ///
  /// C'est le comportement historique de l'application, conservé pour les hôtes
  /// qui ne publient pas leurs espaces.
  private static func espacesDeduits(_ sessions: [SessionListee]) -> [EspaceDeTravail] {
    var parChemin: [String: (nom: String, sessions: [SessionListee])] = [:]
    var ordre: [String] = []

    for session in sessions {
      let (nom, chemin) = nomEspace(session)
      if parChemin[chemin] == nil {
        parChemin[chemin] = (nom, [])
        ordre.append(chemin)
      }
      parChemin[chemin]?.sessions.append(session)
    }

    let espaces = ordre.compactMap { chemin -> EspaceDeTravail? in
      guard let entree = parChemin[chemin] else { return nil }
      return EspaceDeTravail(
        id: chemin,
        nom: entree.nom,
        chemin: chemin,
        sessions: ordonner(entree.sessions),
        sansSession: false,
        horsEspaces: false)
    }

    // Départage par chemin, comme le service hôte (`left.path.localeCompare`) :
    // deux espaces créés dans la même milliseconde doivent garder un ordre
    // stable d'un rafraîchissement à l'autre, sinon l'arbre « saute ».
    return espaces.sorted { gauche, droite in
      let gaucheCree = dateCreationEspace(gauche)
      let droiteCree = dateCreationEspace(droite)
      if gaucheCree != droiteCree { return gaucheCree > droiteCree }
      return gauche.chemin.localizedStandardCompare(droite.chemin) == .orderedAscending
    }
  }

  /// Sous-agents rattachés à une session, pour l'imbrication.
  ///
  /// Le rattachement est INDICATIF : l'en-tête d'un sous-agent ne nomme pas son
  /// parent. On les place donc sous la session racine la plus récente de leur
  /// espace, ce qui correspond à l'usage réel — un sous-agent est lancé par la
  /// session en cours — sans prétendre à une exactitude que la donnée n'a pas.
  public static func sousAgents(de session: SessionListee, dans espace: EspaceDeTravail) -> [SessionListee] {
    guard !estSousAgent(session) else { return [] }
    return espace.sessions.filter { estSousAgent($0) }
  }

  /// Dernière activité d'une session, en secondes.
  ///
  /// C'est la date qui classe les SESSIONS dans un espace.
  static func dateActivite(_ session: SessionListee) -> Double {
    Double(session.resume.dernierEvenementLe ?? 0) / 1000
  }

  /// Création d'une session, en secondes.
  ///
  /// Repli sur l'activité quand le journal ne porte pas de date de création :
  /// une session sans `creeLe` ne doit pas être traitée comme vieille de 1970 et
  /// reléguée en fin de liste — c'est un fait manquant, pas une ancienneté.
  static func dateCreation(_ session: SessionListee) -> Double {
    if let cree = session.resume.creeLe, cree > 0 { return Double(cree) / 1000 }
    return dateActivite(session)
  }

  /// Rang d'un espace : la création de sa session la plus récente.
  ///
  /// Même règle que le service hôte, qui prend `newestAt` — la plus grande date
  /// de création des sessions d'un même chemin — et non leur dernière activité.
  static func dateCreationEspace(_ espace: EspaceDeTravail) -> Double {
    espace.sessions.map(dateCreation).max() ?? 0
  }
}

/// Formate une date en âge court, comme l'interface web : « 1min », « 6h », « 3j ».
public enum AgeLisible {
  public static func texte(_ millisecondes: Int?, maintenant: Date = Date()) -> String {
    guard let millisecondes, millisecondes > 0 else { return "" }
    let secondes = maintenant.timeIntervalSince1970 - Double(millisecondes) / 1000
    guard secondes > 0 else { return L("à l'instant") }
    if secondes < 60 { return "\(Int(secondes))s" }
    if secondes < 3600 { return "\(Int(secondes / 60))min" }
    if secondes < 86400 { return "\(Int(secondes / 3600))h" }
    if secondes < 86400 * 30 { return "\(Int(secondes / 86400))" + L("j") }
    return "\(Int(secondes / (86400 * 30)))" + L("mois")
  }
}
