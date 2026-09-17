import Foundation

/// CE QUE L'INTERFACE **LIT** DU MODÈLE — les dérivations, séparées de l'orchestration.
///
/// POURQUOI CE FICHIER EXISTE. `ModeleApp.swift` portait, mêlées aux boucles réseau et
/// aux transitions d'état, les quelques dérivations que les vues lisent : quelles
/// machines afficher, quelles sessions retenues, quel nom donner à la liste, à quelles
/// étapes en est une machine. Elles ne décident RIEN — elles lisent un état déjà tenu
/// ailleurs —, et c'est ce qui les rend déplaçables sans toucher à la visibilité : un
/// lecteur n'a pas besoin du setter.
///
/// LA CONTRAINTE QUI A DICTÉ CE DÉCOUPAGE, ET QUI VAUT POUR LES SUIVANTS : en Swift,
/// une EXTENSION ne peut pas porter de propriété STOCKÉE. L'état (`sessions`,
/// `serveurs`, `recherche`, `terminees`…) reste donc dans la classe, et seules les
/// MÉTHODES migrent. Un domaine qui entremêle ses propriétés et ses méthodes — comme
/// l'écriture, avec ses brouillons et son acquittement — demande une chirurgie plus
/// fine que ce fichier, et c'est écrit ici pour que personne ne s'y casse les dents.
///
/// CE QUI RESTE DANS `ModeleApp` : une ligne par dérivation déplacée, marquée
/// `DÉRIVATION`. La surface publique ne change pas — les vues et les tests continuent
/// d'appeler les mêmes noms.
extension ModeleApp {

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

  /// Vrai si une fin de tour non vue mérite la pastille verte.
  public func aTermine(_ identifiant: String) -> Bool { terminees.contains(identifiant) }

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
}
