import Foundation

/// L'ÉCRITURE — composer un message, l'envoyer, l'annuler, et ne jamais mentir.
///
/// POURQUOI CE FICHIER EXISTE. Ce domaine tient une douzaine de règles nées de
/// défauts constatés — les brouillons sont PAR COUPLE hôte/session (un texte écrit
/// pour une session partait dans une autre), l'identifiant d'envoi est REJOUÉ tant
/// que l'hôte n'a pas acquitté (sinon une réponse perdue fait un doublon), un
/// acquittement ne s'affiche que sous SA session (sinon l'écran félicite une session
/// qui n'a rien envoyé), et le composeur disparaît quand l'hôte annonce ne pas savoir
/// écrire. Elles étaient mêlées, dans `ModeleApp.swift`, aux boucles réseau et aux
/// transitions de cible.
///
/// LA CONTRAINTE, ÉCRITE ICI POUR NE PAS ÊTRE REDÉCOUVERTE : une extension Swift ne
/// peut pas porter de propriété STOCKÉE. L'état de ce domaine — `brouillons`,
/// `acquittement`, `refus`, `envoiEnAttente`, `envoiEnCours` — reste donc dans la
/// classe, AU MILIEU du fichier d'origine, tandis que ses méthodes vivent ici.
///
/// CE QUE CE DÉPLACEMENT A COÛTÉ, ET QUI EST ASSUMÉ : les membres d'état que ces
/// méthodes touchent ont été ouverts de `private` à `internal` — un relâchement
/// d'encapsulation AU SEIN DU MODULE. La surface PUBLIQUE, elle, ne change pas d'un
/// caractère ; ce qui change est qu'un autre fichier du module peut désormais écrire
/// ces champs. C'est le prix d'un découpage en Swift, et il est préférable à un état
/// dupliqué ou à une classe de 3 400 lignes.
extension ModeleApp {

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
  func cleBrouillon(pour identifiant: String) -> String {
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
}
