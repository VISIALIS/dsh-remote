import Foundation

/// LA LECTURE D'UN JOURNAL — ouvrir une session, la suivre, la refermer.
///
/// POURQUOI CE FICHIER EXISTE. Ce domaine porte une règle qui a coûté un défaut
/// visible, et une seule : **le journal et la session à laquelle il appartient ne
/// doivent jamais se séparer**. Une lecture ÉCHOUÉE laissait l'ancien journal à
/// l'écran pendant que l'en-tête et le titre passaient à la nouvelle session — donc
/// les événements d'une session sous le nom d'une autre, ce qui est pire qu'un écran
/// vide parce que rien ne le signale. D'où `journalPour` : la clé qui rattache le
/// journal affiché à SA session, posée dès l'ouverture et vérifiée à chaque écriture.
///
/// LA CONTRAINTE, RAPPELÉE ICI : une extension Swift ne porte pas de propriété
/// stockée. L'état — `journal`, `journalPour`, `erreurJournal`, `journalEnLecture` —
/// reste dans la classe ; ses méthodes vivent ici.
extension ModeleApp {

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

  public func fermerJournal() {
    arreterFlux()
    viderLeJournal()
  }

  /// Le journal ET ce qui le rattache à sa session.
  ///
  /// UN SEUL ENDROIT, parce que l'oubli d'un des trois champs donne exactement le
  /// défaut qu'on répare : un journal affiché sous le nom d'une autre session.
  func viderLeJournal() {
    journal = []
    sessionOuverte = nil
    journalPour = nil
    erreurJournal = nil
    journalEnLecture = nil
  }
}
