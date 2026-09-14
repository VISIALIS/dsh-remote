import Foundation
import Testing

@testable import DSHRemoteKit

// L'ÉCHANGE D'UN CODE, CÔTÉ APPLICATION — le contrat des refus.
//
// POURQUOI CE FICHIER EXISTE. Le protocole a maintenant TROIS `403` : origine
// refusée (une erreur de client), écriture refusée (une portée insuffisante), et
// échange refusé (un code expiré ou déjà utilisé). Le dépôt a déjà payé deux fois
// la confusion entre deux refus de même code HTTP : « un client natif ne doit
// jamais envoyer d'en-tête Origin » affiché à quelqu'un dont le jeton lisait
// simplement sans écrire. La troisième ne doit pas coûter la même heure.
//
// CE QUI EST ÉPROUVÉ ICI :
//
//   1. un `403` de code devient `appairageRefuse`, jamais `origineRefusee` ;
//   2. les DEUX motifs connus de l'hôte sont TRADUITS — l'hôte écrit en ASCII sans
//      accent, une interface française ne doit pas afficher « code expire » ;
//   3. un motif inconnu est affiché tel quel plutôt qu'inventé ;
//   4. un `404` dit « hôte trop ancien », pas « code invalide » : deux causes, deux
//      remèdes, et l'un se répare en mettant le plugin à jour.
//
// Les chaînes « code expire » et « code inconnu ou deja utilise » sont des termes
// du CONTRAT : le plugin les écrit (`dynamic/host.js`, tenues par
// `plugins/dsh-remote/tests/hote.test.js`), l'application les reconnaît ici.

private func corps(_ json: String) -> Data { Data(json.utf8) }

@Test("Un 403 de code devient un refus d'appairage, pas un refus d'origine")
func refusDeCodeReconnu() {
  let expire = RemoteClient.erreur(
    pour: 403,
    donnees: corps(#"{"erreur":"code expire","detail":"redemandez un code dans le panneau « Appairer un appareil »"}"#))
  guard case let .appairageRefuse(motif, detail) = expire else {
    Issue.record("attendu : appairageRefuse, obtenu : \(expire)")
    return
  }
  // LE MOTIF EST GARDÉ TEL QUEL — c'est lui qui identifie la cause, et donc le
  // remède traduit. Le détail vit à part.
  #expect(motif == ErreurRemote.motifCodeExpire)
  #expect(detail?.isEmpty == false)

  let dejaServi = RemoteClient.erreur(
    pour: 403, donnees: corps(#"{"erreur":"code inconnu ou deja utilise","detail":"les codes ne servent qu une fois"}"#))
  guard case let .appairageRefuse(motifInconnu, _) = dejaServi else {
    Issue.record("attendu : appairageRefuse, obtenu : \(dejaServi)")
    return
  }
  #expect(motifInconnu == ErreurRemote.motifCodeInconnu)
}

@Test("Les deux motifs connus sont traduits, jamais affichés bruts")
func motifsTraduits() {
  // POURQUOI CES ASSERTIONS SONT INDÉPENDANTES DE LA LANGUE. Le premier jet
  // affirmait des sous-chaînes françaises — et il est tombé sur une machine dont
  // la langue est l'anglais, ce qui est exactement le piège que la traduction est
  // censée éviter. On affirme donc la PROPRIÉTÉ : le motif ASCII de l'hôte n'est
  // pas recopié tel quel, les deux motifs ne se confondent pas, et le geste est
  // nommé — quelle que soit la langue de la machine.
  let geste = L("demandez un nouveau code dans le panneau « Appairer un appareil » du Mac.")

  let expire = ErreurRemote.appairageRefuse(motif: ErreurRemote.motifCodeExpire, detail: nil)
  #expect(expire.description.contains(ErreurRemote.motifCodeExpire) == false, "le motif ASCII de l hote ne doit pas être affiché brut")
  #expect(expire.description.contains(geste), "le remède doit être nommé")
  #expect(expire.description.contains("Origin") == false)
  #expect(expire.description.contains("403") == false)

  let inconnu = ErreurRemote.appairageRefuse(motif: ErreurRemote.motifCodeInconnu, detail: nil)
  #expect(inconnu.description.contains(ErreurRemote.motifCodeInconnu) == false)
  #expect(inconnu.description.contains(geste))
  // DEUX CAUSES, DEUX PHRASES : si les deux rendaient le même texte, l'utilisateur
  // ne pourrait pas distinguer « expiré » de « déjà servi ».
  #expect(expire.description != inconnu.description)
}

@Test("Un motif inconnu est affiché tel quel, jamais inventé")
func motifInconnuAffiche() {
  // Un hôte plus récent peut refuser pour une cause que cette application ne
  // connaît pas. L'inventer serait pire que l'afficher : un remède faux envoie
  // chercher au mauvais endroit.
  let erreur = ErreurRemote.appairageRefuse(motif: "code revocation en cours", detail: "reessayez dans une minute")
  #expect(erreur.description.contains("reessayez dans une minute"), "le détail de l hôte doit être montré")
  #expect(erreur.description.contains(L("demandez un nouveau code dans le panneau « Appairer un appareil » du Mac.")))
}

@Test("Un 404 sur l'échange dit « hôte trop ancien », pas « code invalide »")
func hoteSansRouteDEchange() {
  // `echange: true` : c'est la SEULE route où un 404 accuse le plugin d'en face.
  let erreur = RemoteClient.erreur(pour: 404, donnees: Data(), echange: true)
  guard case .appairageNonSupporte = erreur else {
    Issue.record("attendu : appairageNonSupporte, obtenu : \(erreur)")
    return
  }
  // PROPRIÉTÉS INDÉPENDANTES DE LA LANGUE : le message existe, ne montre aucun
  // code HTTP, et NE PARLE PAS de code d'appairage — le code n'est pas en cause,
  // c'est le plugin d'en face qui est trop ancien.
  #expect(erreur.description.isEmpty == false)
  #expect(erreur.description.contains("404") == false)
  #expect(erreur.description != ErreurRemote.appairageRefuse(motif: ErreurRemote.motifCodeExpire, detail: nil).description)
}

@Test("Un 429 d'échange reste un refus serveur, avec son motif")
func tropDEchanges() {
  // Le plafond de la route est GLOBAL (mesuré : derrière `tailscale serve`,
  // l'adresse source est toujours la boucle locale). Ce n'est donc pas un refus
  // d'appairage : c'est un « réessayez », et le message doit le dire.
  let erreur = RemoteClient.erreur(
    pour: 429, donnees: corps(#"{"erreur":"trop d echanges","detail":"patientez une minute avant de recommencer"}"#))
  guard case let .refusServeur(statut, motif, _) = erreur else {
    Issue.record("attendu : refusServeur, obtenu : \(erreur)")
    return
  }
  #expect(statut == 429)
  #expect(motif.contains("patientez"))
}

@Test("Les autres 403 ne changent pas de sens")
func autres403Inchanges() {
  // LA NON-RÉGRESSION LA PLUS IMPORTANTE DE CE FICHIER : ajouter un troisième sens
  // au 403 ne doit pas absorber les deux premiers.
  let portee = RemoteClient.erreur(
    pour: 403, donnees: corps(#"{"erreur":"jeton en lecture seule","portee":"lecture"}"#))
  guard case .ecritureRefusee = portee else {
    Issue.record("attendu : ecritureRefusee, obtenu : \(portee)")
    return
  }
  let origine = RemoteClient.erreur(pour: 403, donnees: corps(#"{"erreur":"origine refusee"}"#))
  guard case .origineRefusee = origine else {
    Issue.record("attendu : origineRefusee, obtenu : \(origine)")
    return
  }
  let muet = RemoteClient.erreur(pour: 403, donnees: Data())
  guard case .origineRefusee = muet else {
    Issue.record("attendu : origineRefusee, obtenu : \(muet)")
    return
  }
}

@Test("Un 404 AILLEURS ne parle pas du plugin : il nomme la session inconnue")
func sessionInconnueNEstPasUnPluginAncien() {
  // LE DÉFAUT MESURÉ, ET SON COÛT. `journal <identifiant>` sur une session
  // inconnue répondait `404` : le client le traduisait en « votre plugin est plus
  // ancien, mettez-le à jour » — un remède faux, qui envoie chercher au mauvais
  // endroit. L'hôte, lui, dit exactement ce qui manque : « session inconnue ».
  let corps = Data(#"{"erreur":"session inconnue"}"#.utf8)
  let erreur = RemoteClient.erreur(pour: 404, donnees: corps)
  guard case let .refusServeur(statut, motif, _) = erreur else {
    Issue.record("attendu : refusServeur(404), obtenu : \(erreur)")
    return
  }
  #expect(statut == 404)
  #expect(motif.contains("session inconnue"), "le motif de l'hôte doit être montré : \(motif)")
  // ET LE MESSAGE NE PARLE PAS DU PLUGIN : c'est la propriété qui compte.
  let phrase = erreur.description
  #expect(phrase.contains("plugin") == false, "aucun remède qui n'existe pas : \(phrase)")
  #expect(phrase.contains("404"), "le statut situe la panne : \(phrase)")
}
