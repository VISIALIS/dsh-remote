import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// LE DOMAINE DES WIDGETS ET DES ACTIVITÉS EN DIRECT (Live Activities).
///
/// POURQUOI CE FICHIER EXISTE.
/// L'application partage son état d'affichage avec les extensions WidgetKit (écran
/// d'accueil, Dynamic Island, écran verrouillé, centre de notifications).
/// RÈGLE #0 : aucun secret, aucun jeton d'authentification n'est partagé.
/// Seul un instantané synthétique d'affichage (`InstantaneWidget`) est déposé
/// dans le conteneur partagé App Group.
extension ModeleApp {

  /// Un lien de widget. Les URL d'appairage (`dshremote://<machine>/…`) sont ignorées.
  public func recevoirLien(_ url: URL) {
    switch LienWidget.lire(url) {
    case let .session(identifiant):
      pageServeurDemandee = false
      sessionDemandeeParLien = identifiant
    case .serveur:
      sessionDemandeeParLien = nil
      pageServeurDemandee = true
    case nil:
      break
    }
  }


  // MARK: - L'instantané du widget

  /// Actualise l'instantané partagé avec le widget et synchronise les Live Activities.
  public func actualiserInstantaneWidget() {
    let actives = sessions.filter { $0.vivante == true || $0.statut != nil }
    let auTravail = sessions.filter { $0.statut == "en_cours" }
    let sessionAuTravail = auTravail.first
    let derniere = sessionAuTravail ?? sessions.first

    let sommaireDerniere: SommaireSessionWidget?
    if let derniere {
      let etatCalcule = EtatSession.de(derniere, rappelDeFin: aTermine(derniere.id))
      sommaireDerniere = SommaireSessionWidget(
        identifiant: derniere.id,
        titre: derniere.titreAffiche,
        espaceNom: derniere.projet ?? derniere.dossier ?? "",
        etat: derniere.statut ?? "inactif",
        derniereEtape: etatCalcule.libelle,
        dateDerniereActivite: derniere.modifieLe.map { Date(timeIntervalSince1970: $0) } ?? Date()
      )
    } else {
      sommaireDerniere = nil
    }

    let estConnecte: Bool
    switch connexion {
    case .jointe: estConnecte = true
    default: estConnecte = false
    }

    let instantane = InstantaneWidget(
      dateMiseAJour: Date(),
      nomServeur: nomServeur ?? (adresse.isEmpty ? "DSH" : adresse),
      adresseServeur: adresse,
      estConnecte: estConnecte,
      nombreSessionsActives: actives.count,
      nombreSessionsAuTravail: auTravail.count,
      derniereSession: sommaireDerniere
    )

    persistance.memoriserInstantaneWidget(instantane)

    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif

    // Synchronisation de la Live Activity (Dynamic Island / écran verrouillé)
    GestionnaireActivitesLive.shared.synchroniser(
      session: sessionAuTravail,
      nomServeur: nomServeur ?? (adresse.isEmpty ? "DSH" : adresse),
      derniereEtape: sessionAuTravail == nil ? nil : sommaireDerniere?.derniereEtape,
      horodatageEtape: ReleveDActivite.horodatage(modifieLe: sessionAuTravail?.modifieLe)
    )
  }
}
