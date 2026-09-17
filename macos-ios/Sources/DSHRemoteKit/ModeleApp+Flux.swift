import Foundation

/// LE FLUX — suivre une session en direct, et ne jamais rester muet.
///
/// POURQUOI CE FICHIER EXISTE. Ce domaine porte les règles les plus coûteuses du
/// client, et toutes sont nées d'un défaut constaté : la reprise par `depuisSeq` (une
/// reconnexion ne doit ni perdre ni dupliquer), la réouverture AUTOMATIQUE après une
/// coupure (l'utilisateur ne doit pas rappuyer sur un bouton), le battement de cœur
/// (une socket morte sans le dire laissait « En direct » sur un journal figé), le
/// quota de reconnexion remis à neuf au retour au premier plan (le sommeil n'est pas
/// une panne), et l'arrêt des boucles en arrière-plan (la radio et le quota).
///
/// LA CONTRAINTE, RAPPELÉE ICI : une extension Swift ne porte pas de propriété
/// stockée. L'état du flux (`flux`, `tacheFlux`, `tacheReconnexion`, `reconnexion`,
/// `enDirect`, `journalPour`, `sessionOuverte`, `journal`, `dernierSeqVu`) reste dans
/// la classe ; ses méthodes vivent ici.
///
/// CE QUE CE DÉPLACEMENT A COÛTÉ, ET QUI EST ASSUMÉ : quatorze membres sont passés de
/// `private` à `internal` (dont les setters `private(set)` de `reconnexion`,
/// `enDirect`, `journalPour`, `sessionOuverte`, `journal`, `connexion`). La surface
/// PUBLIQUE ne change pas ; ce qui change est qu'un autre fichier du module peut
/// écrire ces champs. C'est le prix d'un découpage en Swift, et il est préférable à
/// une classe de 3 300 lignes.
extension ModeleApp {

  /// Suit la session en direct, en reprenant au dernier `seq` déjà chargé.
  ///
  /// La reprise n'est pas un confort : sans `depuisSeq`, le serveur renverrait
  /// tout ce que la page vient de charger, et le journal afficherait des doublons.
  ///
  /// LE MESSAGE D'ERREUR N'ARRÊTE PLUS LE SUIVI. Il enregistre un échec, et le
  /// flux est rouvert après un délai qui double — voir `Reconnexion`. Ce qui
  /// arrête pour de bon, c'est le quota de tentatives épuisé, ou le geste de
  /// l'utilisateur.
  public func demarrerFlux(_ identifiant: String) async {
    await fermerLeFluxCourant()
    // UN SUIVI NEUF REPART D'UN COMPTEUR NEUF : les échecs de la session qu'on
    // vient de quitter ne disent rien de celle-ci.
    reconnexion = Reconnexion()
    enDirect = true
    let jeton = jetonSaisi
    let adresse = self.adresse
    // LE `seq` VIENT DU JOURNAL AFFICHÉ, pas d'un compteur : c'est ce qui rend la
    // reprise non destructive, y compris après une reconnexion.
    let depuis = journal.last?.enregistrement.seq
    await ouvrirLeFlux(identifiant, adresse: adresse, jeton: jeton, depuisSeq: depuis)
  }

  /// Ouvre une socket de flux et l'écoute, en décidant quoi faire de sa fin.
  private func ouvrirLeFlux(_ identifiant: String, adresse: String, jeton: String, depuisSeq: Int?) async {
    guard client != nil else { return }
    guard
      let session = FluxSession(adresse: adresse, jeton: jeton, identifiant: identifiant, depuisSeq: depuisSeq)
    else { return }
    flux = session
    let tache = Task { [weak self] in
      for await message in await session.messages() {
        guard let self else { return }
        await self.appliquer(message, pour: identifiant, adresse: adresse, jeton: jeton)
      }
    }
    tacheFlux = tache
  }

  /// Ferme le flux courant ET la reconnexion en vol, sans toucher à l'état visible.
  private func fermerLeFluxCourant() async {
    tacheFlux?.cancel()
    tacheFlux = nil
    tacheReconnexion?.cancel()
    tacheReconnexion = nil
    if let precedent = flux { await precedent.fermer() }
    flux = nil
  }

  /// Arrête le suivi. Le journal déjà chargé reste affiché.
  ///
  /// C'EST LE GESTE DE L'UTILISATEUR, donc il arrête AUSSI la reconnexion : sans
  /// cela, « Suivi arrêté » se rallumerait tout seul une seconde plus tard, et le
  /// bouton mentirait.
  public func arreterFlux() {
    Task { await fermerLeFluxCourant() }
    enDirect = false
    reconnexion = nil
  }

  // MARK: - Le cycle de vie de l'application

  /// SUSPENDRE LE TRAVAIL DE FOND — sur `scenePhase == .background`.
  ///
  /// POURQUOI ÇA EXISTE. Trois boucles et une socket continuaient de « tourner »
  /// pendant qu'iOS gèle le processus : entre le passage en arrière-plan et la
  /// suspension, elles consommaient de la radio pour rien, et surtout la
  /// temporisation de reconnexion reprenait au réveil avec un quota entamé — le
  /// cas « l'application a dormi dix minutes et le flux affiche un échec ».
  ///
  /// CE QUI EST FERMÉ, ET CE QUI EST GARDÉ. On ferme la socket et la reconnexion
  /// en vol (`fermerLeFluxCourant`), on arrête les deux boucles. On NE touche PAS
  /// à `enDirect` : c'est l'INTENTION de l'utilisateur — « je suivais cette
  /// session » — et c'est elle qui décide de la réouverture. L'éteindre ici
  /// ferait disparaître le direct au retour, sans que personne ne l'ait demandé.
  ///
  /// `.inactive` N'ARRÊTE RIEN, ET C'EST DÉLIBÉRÉ : iOS passe par cet état pour
  /// le sélecteur d'applications, une bannière ou le centre de contrôle. Y couper
  /// le flux le romprait à chaque notification.
  public func suspendreLeTravailDeFond() async {
    guard !enArrierePlan else { return }
    enArrierePlan = true
    arreterSuivi()
    arreterSuiviServeurs()
    await fermerLeFluxCourant()
    Trace.siActive("[cycle] arriere-plan : boucles arretees, flux ferme, quota intact")
  }

  /// REPRENDRE AU PREMIER PLAN — sur `scenePhase == .active`.
  ///
  /// TROIS CHOSES, DANS CET ORDRE, ET CHACUNE RÉPARE UN DÉFAUT CONSTATÉ :
  ///
  /// 1. **le quota de reconnexion repart à neuf.** Vingt tentatives, c'est la
  ///    bonne politique pour un jeton révoqué ; c'est la mauvaise pour une
  ///    application qui a dormi. Le compteur décrit une panne EN COURS, et le
  ///    sommeil n'en est pas une ;
  /// 2. **un rafraîchissement immédiat**, sans attendre le premier tic de la
  ///    boucle : l'utilisateur qui rouvre l'application doit voir l'état de
  ///    maintenant, pas celui d'il y a un quart d'heure ;
  /// 3. **la réouverture du flux**, avec `depuisSeq` — donc sans doublon et sans
  ///    perte. C'est exactement ce pour quoi la reprise a été conçue.
  public func reprendreLeTravailDeFond() async {
    guard enArrierePlan else { return }
    enArrierePlan = false
    await rafraichirSilencieusement()
    await synchroniserServeurs()
    demarrerSuivi()
    demarrerSuiviServeurs()
    // LE QUOTA EST REMIS À NEUF ICI, ET NON PLUS HAUT : un compteur de
    // reconnexion ne décrit quelque chose que s'il y a un flux à rouvrir. Le
    // remettre à neuf sans flux laisserait un « Reconnexion… » à l'écran pour un
    // suivi qui n'existe pas — la barre d'outils lit `reconnexion` AVANT
    // `enDirect`.
    if enDirect, let identifiant = journalPour ?? sessionOuverte?.id {
      reconnexion = Reconnexion()
      await demarrerFlux(identifiant)
    }
    Trace.siActive("[cycle] premier plan : liste relue, boucles reprises, flux rouvert si demande")
  }

  // MARK: - Le chemin réseau

  /// Observe le chemin réseau et réagit à ses changements, jusqu'à annulation.
  ///
  /// POURQUOI ELLE EXISTE. La détection du tailnet était une mesure ponctuelle
  /// (`getifaddrs`) : juste, mais muette sur les CHANGEMENTS. Activer Tailscale,
  /// couper le Wi-Fi, passer en 5G, sortir d'une zone blanche — l'application ne
  /// l'apprenait qu'à l'échec de la requête suivante. `NWPathMonitor` notifie ces
  /// changements, et cette boucle en fait trois choses : elle REMESURE le fait
  /// « cet appareil est sur le tailnet », elle REPREND ce qui avait échoué quand le
  /// chemin revient, et elle ralentit le suivi sur un chemin coûteux.
  public func observerLeChemin() async {
    guard let observateurDeChemin else { return }
    observateurDeChemin.demarrer()
    for await etat in observateurDeChemin.changements() {
      if Task.isCancelled { return }
      await appliquerChemin(etat)
    }
  }

  /// Applique un état de chemin — la règle, éprouvable sans réseau.
  func appliquerChemin(_ etat: CheminReseau.Etat) async {
    chemin = etat
    // LA MESURE PONCTUELLE EST REFAITE ICI : c'est elle qui sait si l'appareil est
    // SUR le tailnet (une adresse 100.64.0.0/10) — `NWPathMonitor` ne publie pas
    // l'état d'un tunnel VPN. L'observateur la DÉCLENCHE, il ne la remplace pas.
    relireEtatTailscale()
    guard etat.disponible else {
      Trace.siActive("[chemin] indisponible : aucune reprise tentee")
      return
    }
    guard CheminReseau.doitReprendre(chemin: etat, jointe: hoteEstJoint) else { return }
    // LE CHEMIN REVIENT, ET LA CIBLE N'EST PAS JOINTE : on refait ce que le
    // démarrage aurait fait. C'est le cas « fin de zone blanche », celui où
    // l'utilisateur attend sans rien toucher.
    Trace.siActive("[chemin] revenu sans cible jointe : reprise")
    await connecter()
  }

  /// Applique un message du flux au journal affiché.
  ///
  /// Un `seq` déjà présent est ignoré : une reprise peut recouvrir la page
  /// chargée, et un doublon à l'écran serait un défaut visible.
  private func appliquer(_ message: MessageFlux, pour identifiant: String, adresse: String, jeton: String) async {
    switch message {
    case let .base(_, enregistrements, _):
      for enregistrement in enregistrements {
        ajouterSiNouveau(enregistrement)
      }
      reconnexion?.reussite()
    case let .evenement(enregistrement):
      ajouterSiNouveau(enregistrement)
      // UN CONTENU REÇU PROUVE QUE LE FLUX VIT — c'est le seul signal qui remette
      // le compteur à zéro (voir `Reconnexion.reussite`).
      reconnexion?.reussite()
    case let .delta(dernierSeq):
      if let dernierSeq { dernierSeqVu = dernierSeq }
    case let .statut(statut):
      // LE STATUT PASSE PAR L'ÉCRIVAIN NOMMÉ, avec la génération du départ : un
      // statut poussé par une machine qu'on vient de quitter décrit une autre
      // cible, et la garde le refuse comme les autres réponses.
      appliquerStatut(statut, de: identifiant, vu: generationDuDepart())
    case let .tronque(detail):
      connexion = .echec(.transport("Flux incomplet : \(detail)"))
    case let .erreur(detail):
      await prevenirEtReconnecter(detail, identifiant: identifiant, adresse: adresse, jeton: jeton)
    }
  }

  /// Le flux est tombé : le dire, puis rouvrir — ou renoncer.
  ///
  /// L'ERREUR EST TOUJOURS MONTRÉE, même quand on va réessayer : l'utilisateur doit
  /// savoir que le direct est interrompu, sinon il attendrait des nouvelles d'un
  /// journal qui n'en recevra pas. La reconnexion, elle, efface ce message dès
  /// qu'elle aboutit.
  private func prevenirEtReconnecter(_ detail: String, identifiant: String, adresse: String, jeton: String) async {
    connexion = .echec(.transport(detail))
    guard var etat = reconnexion, let delai = etat.echec() else {
      // QUOTA ÉPUISÉ : on s'arrête POUR DE BON, et on le dit une fois. Réessayer
      // sans fin devant un `401` ferait clignoter l'écran pour toujours.
      enDirect = false
      reconnexion = nil
      return
    }
    reconnexion = etat
    // L'ADRESSE ET LA SESSION SONT REVÉRIFIÉES APRÈS L'ATTENTE : pendant ces
    // quelques secondes, l'utilisateur a pu changer de machine ou de session.
    // Rouvrir dans ce cas connecterait le flux à la mauvaise cible — le défaut que
    // la « génération » corrige partout ailleurs.
    //
    // LA SESSION SE LIT DANS `journalPour`, ET PAS DANS `sessionOuverte` : c'est une
    // correction, et un test l'a attrapée. `sessionOuverte` n'est renseigné qu'APRÈS
    // une lecture de journal réussie — une session dont la lecture échoue (ou n'a
    // pas encore abouti) n'aurait donc JAMAIS repris son flux, tout en affichant
    // « En direct ». `journalPour` est la clé du journal affiché : posée dès
    // l'ouverture, effacée au changement de cible. C'est exactement ce que le flux
    // doit suivre.
    let cible = adresse
    tacheReconnexion = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(delai * 1_000_000_000))
      guard !Task.isCancelled, let self else { return }
      guard self.adresse == cible, self.journalPour == identifiant else { return }
      await self.ouvrirLeFlux(identifiant, adresse: cible, jeton: jeton, depuisSeq: self.journal.last?.enregistrement.seq)
    }
  }

  private func ajouterSiNouveau(_ enregistrement: EnregistrementJournal) {
    if let seq = enregistrement.seq, journal.contains(where: { $0.enregistrement.seq == seq }) {
      return
    }
    journal.append(DecodeurEvenement.afficher(enregistrement))
  }
}
