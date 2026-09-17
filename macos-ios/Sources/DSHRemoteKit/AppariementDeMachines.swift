import Foundation

/// L'APPARIEMENT DES MACHINES — quelles adresses désignent la même machine.
///
/// POURQUOI CE FICHIER EXISTE. Ces six règles vivaient dans `ModeleApp.swift`, qui
/// dépasse 3 400 lignes : elles ne dépendent NI de l'état du modèle NI de l'interface,
/// seulement d'une adresse et d'une liste de machines — et ce sont elles qui décident
/// si l'écran parle de la machine qu'il croit. Les sortir rend la question « deux
/// écritures désignent-elles le même hôte ? » lisible en une page, sans lire un modèle
/// de 3 400 lignes.
///
/// `ModeleApp` en garde des DÉLÉGATIONS d'une ligne : la surface publique ne change
/// pas (les vues et les tests appellent toujours `ModeleApp.serveurA`), mais la règle
/// vit ici, et une seule fois.
///
/// CE QUI LES REND JUSTES, ET QUI A COÛTÉ DES DÉFAUTS : l'identité d'un hôte est son
/// NOM et son PORT, jamais son transport (`IdentiteHote.cle`). Comparer les adresses
/// complètes faisait qu'une adresse mémorisée en clair ne reconnaissait plus la même
/// machine publiée en HTTPS — la vignette perdait son nom et son icône pour un simple
/// changement de transport.
public enum AppariementDeMachines {

  /// Version PURE — même normalisation que `serveurHorsLigne`, éprouvable seule.
  ///
  /// LA COMPARAISON PORTE SUR L'IDENTITÉ DE L'HÔTE (`IdentiteHote.cle`), donc sur
  /// le nom et le port : le schéma n'en fait plus partie, parce que la même
  /// machine en `http` et en `https` est LA MÊME. Comparer les adresses complètes
  /// faisait qu'une adresse mémorisée en clair ne reconnaissait plus la machine
  /// publiée en HTTPS — la vignette perdait son nom et son icône pour un simple
  /// changement de transport.
  nonisolated static func serveurA(adresse: String, dans serveurs: [ServeurMac]) -> ServeurMac? {
    let visee = IdentiteHote.cle(adresse)
    guard !visee.isEmpty else { return nil }
    return serveurs.first { serveur in
      IdentiteHote.cle(serveur.adresse) == visee
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
    let gauche = IdentiteHote.cle(adresse)
    guard !gauche.isEmpty else { return false }
    return gauche == IdentiteHote.cle(serveur.adresse)
  }
  /// `127.0.0.1`, `localhost`, `::1` — la boucle locale, et rien d'autre.
  nonisolated static func estBoucleLocale(_ adresse: String) -> Bool {
    guard let brut = ExceptionATS.hote(adresse)?.lowercased() else { return false }
    // `URLComponents` rend l'hôte IPv6 tantôt entre crochets, tantôt nu selon la
    // forme de l'adresse : les deux se ramènent à la même chose.
    let hote = brut.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    return hote == "localhost" || hote == "127.0.0.1" || hote == "::1"
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
    "« \(serveur.nom) » "
      + L("est hors ligne sur le tailnet. Allumez-le, ou choisissez une machine en ligne : la liste se rafraîchit toute seule.")
  }
  /// L'ADRESSE EFFECTIVE D'UNE SAISIE — la règle du paquet, en un seul endroit.
  ///
  /// POURQUOI UNE FONCTION, ET POURQUOI ELLE EST ICI. Trois chemins écrivent
  /// l'adresse visée : la saisie manuelle, l'appairage, et la préférence
  /// mémorisée à la réouverture. Chacun appliquait — ou n'appliquait pas — la
  /// règle du schéma. Une adresse en clair vers un nom qualifié, dans un paquet
  /// sans exception ATS, est un refus CERTAIN : la viser quand même ferait
  /// afficher une panne de réseau là où le remède est connu d'avance.
  ///
  /// CE QUI N'EST PAS RÉÉCRIT : `https` n'est jamais rétrogradé, une IP littérale
  /// ou `localhost` reste en clair (ATS ne les concerne pas, et le PORT est
  /// conservé — `http://100.x.y.z:3080` est une adresse qui marche), et une
  /// adresse vide reste vide.
  nonisolated static func adresseEffective(_ valeur: String) -> String {
    let propre = valeur.trimmingCharacters(in: .whitespacesAndNewlines)
    if propre.isEmpty { return propre }
    if propre.lowercased().hasPrefix("https://") { return propre }
    if propre.lowercased().hasPrefix("http://") {
      return AdresseMachine.pour(hote: String(propre.dropFirst("http://".count)))
    }
    return AdresseMachine.pour(hote: propre)
  }
}
