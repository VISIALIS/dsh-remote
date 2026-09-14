import Foundation

/// CE QUE LE VOLET DE DÉTAIL MONTRE — une règle, pas un enchaînement de `if`.
///
/// POURQUOI CE TYPE EXISTE. La règle vivait dans la vue, en cinq branches
/// enchaînées, et elle finissait sur « Aucune session ouverte » : au lancement,
/// sur macOS comme sur iPad, l'écran de droite restait donc VIDE alors qu'une
/// machine était sélectionnée — et l'utilisateur devait cliquer une vignette pour
/// apprendre ce qu'il avait sous les yeux. La règle demandée est :
///
///   1. **le premier serveur de la liste est sélectionné par défaut**, et sa page
///      de détail s'affiche — jusqu'à ce qu'une session soit choisie ;
///   2. **s'il n'y a aucun serveur**, c'est la page d'ajout qui s'affiche.
///
/// POURQUOI ELLE EST SORTIE DE LA VUE. C'est une décision — quel écran pour quel
/// état —, et elle se vérifie sans rendre une vue : cinq cas, une fonction pure,
/// des tests. Dans la vue, elle n'était éprouvable qu'en pilotant une interface.
///
/// CE QU'ELLE NE FAIT PAS. Elle ne choisit pas la machine à CONNECTER (la
/// « cible », qui préfère une machine en ligne et se souvient du dernier choix) :
/// elle décide seulement ce qu'on REGARDE. Les deux notions sont distinctes dans
/// cette application, et c'est délibéré — la page d'une machine peut s'ouvrir
/// sans qu'on soit connecté à elle.
public enum DetailAffiche: Equatable {
  /// Le journal d'une session — la seule chose qui passe avant tout le reste.
  case journal(String)
  /// La page d'ajout d'un serveur.
  case ajout
  /// La page d'une machine.
  case serveur(ServeurMac)
  /// Rien à montrer — il ne reste que ce cas quand il n'y a ni session, ni
  /// serveur, ni ajout en cours, ce qui ne devrait pas arriver : il est gardé
  /// pour que l'absence de réponse ne soit jamais confondue avec un écran vide
  /// décidé.
  case rien

  /// LA RÈGLE, DANS L'ORDRE OÙ LES CAS SE PRÉSENTENT.
  ///
  /// - Parameters:
  ///   - session: la session choisie dans la liste, s'il y en a une.
  ///   - ajout: la page d'ajout est-elle ouverte ?
  ///   - pageOuverte: la machine dont la page a été ouverte explicitement.
  ///   - cibleEnErreur: la machine visée, quand une erreur l'attend — une erreur
  ///     concerne une machine, et sans cette branche elle ne s'afficherait nulle
  ///     part.
  ///   - vise: la machine visée par la connexion (la « cible »).
  ///   - serveursAffiches: les machines dans l'ordre où elles S'AFFICHENT — celui
  ///     du carrousel (`ModeleApp.serveursAffiches`, joignables d'abord). Le nom
  ///     dit laquelle des deux listes passer : la règle doit tomber sur la MÊME
  ///     machine que la première vignette, sinon la vignette mise en avant et la
  ///     page affichée parlent de deux machines différentes.
  public static func pour(
    session: String?,
    ajout: Bool,
    pageOuverte: ServeurMac?,
    cibleEnErreur: ServeurMac?,
    vise: ServeurMac?,
    serveursAffiches: [ServeurMac]
  ) -> DetailAffiche {
    if let session { return .journal(session) }
    if ajout { return .ajout }
    if let serveur = pageOuverte ?? cibleEnErreur ?? vise { return .serveur(serveur) }
    // LE PREMIER DE LA LISTE AFFICHÉE, ET PAS « RIEN ». C'est la règle demandée :
    // au lancement, une machine est sélectionnée, donc une page est affichée. Le
    // cas se présente quand AUCUNE machine n'est en ligne : il n'y a alors aucune
    // cible — et c'est justement la page de la première qui explique pourquoi.
    if let premier = serveursAffiches.first { return .serveur(premier) }
    // AUCUN SERVEUR : la seule chose utile à montrer est comment en ajouter un.
    return .ajout
  }
}
