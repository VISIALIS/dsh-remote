import Foundation
import Testing

@testable import DSHRemoteKit

// L'APPAIRAGE APPLIQUÉ AU MODÈLE — le geste, pas seulement l'analyse.
//
// POURQUOI CE FICHIER EXISTE. `AppairageTests` éprouve l'ANALYSE d'une charge
// utile ; il ne dit rien de ce que l'application en FAIT. Or c'est là que se
// trouve le seul vrai danger : l'adresse et le jeton vont ENSEMBLE, et
// `viser` recharge le jeton gardé pour la nouvelle machine. Les engager dans le
// mauvais ordre enverrait à un hôte le secret d'un autre — un refus `401` dont
// personne ne trouverait la cause, puisque les deux valeurs seraient bonnes…
// pour des machines différentes.
//
// ET DEPUIS L'ÉTAPE B, IL Y A PIRE QU'UN ORDRE : UN ÉCHANGE. Un code doit être
// échangé contre un jeton AVANT d'être rangé ; ranger le code lui-même enverrait
// 22 caractères comme jeton porteur, et rendrait un `401` qui ferait chercher une
// panne d'authentification là où il manque un échange. C'est éprouvé ci-dessous,
// avec un transport factice : ni réseau, ni harness.
//
// Les valeurs sont FICTIVES et le disent (RÈGLE #0, interdit #8) : domaine
// réservé `.test`, secrets en clair reconnaissables.

private let chargeJeton =
  "dshremote://mac-mini-essai.exemple.test/jeton/v1/JETONFICTIF-a-remplacer-0000000000000000000"
private let jetonAttendu = "JETONFICTIF-a-remplacer-0000000000000000000"
private let chargeCode = "dshremote://mac-mini-essai.exemple.test/code/v1/CODEFICTIF000000000000"
private let codeAttendu = "CODEFICTIF000000000000"
private let jetonEchange = "JETONDECHANGE-fictif-000000000000000000000000"

/// Un transport factice : il rend ce qu'on lui dit, et RETIENT ce qu'on lui demande.
private final class TransportFactice: @unchecked Sendable {
  private let verrou = NSLock()
  private(set) var demandes: [(adresse: String, code: String, nom: String)] = []
  var resultat: Result<AppareilAppaire, Error>

  init(resultat: Result<AppareilAppaire, Error>) { self.resultat = resultat }

  func connexion() -> Connexion {
    // LA FABRIQUE REÇOIT L'ADRESSE ET LE CODE : c'est le transport qui les
    // connaît, pas la méthode d'échange (qui ne reçoit que le nom). Les noter ici
    // est ce qui permet de vérifier QUE L'ÉCHANGE A VISÉ LA BONNE MACHINE avec le
    // bon code — la seule chose que ce test doit prouver.
    Connexion(fabrique: { [self] adresse, code, _ in
      noter(adresse: adresse, code: code)
      return ClientEchange(transport: self)
    })
  }

  private var enAttente: (adresse: String, code: String)?

  func noter(adresse: String, code: String) {
    verrou.lock()
    defer { verrou.unlock() }
    enAttente = (adresse, code)
  }

  func noterNom(_ nom: String) {
    verrou.lock()
    defer { verrou.unlock() }
    guard let attente = enAttente else { return }
    demandes.append((attente.adresse, attente.code, nom))
    enAttente = nil
  }

  /// Le client que la fabrique rend : seule la méthode d'échange sert ici, et les
  /// autres échouent FRANCHEMENT — un faux qui rendrait des valeurs inventées
  /// laisserait passer un appel qu'on n'attendait pas.
  struct ClientEchange: ClientDSH {
    let transport: TransportFactice

    func echangerAppairage(nom: String) async throws -> AppareilAppaire {
      transport.noterNom(nom)
      return try transport.resultat.get()
    }

    func verifierSante() async throws -> Sante { throw ErreurRemote.reponseInattendue(code: 500) }
    func listerSessions(limite: Int?) async throws -> ListeSessions { throw ErreurRemote.reponseInattendue(code: 500) }
    func listerServeurs() async throws -> ListeServeurs { throw ErreurRemote.reponseInattendue(code: 500) }
    func listerEspaces() async throws -> ListeEspaces { throw ErreurRemote.reponseInattendue(code: 500) }
    func lireSession(_ identifiant: String, demande: DemandeJournal) async throws -> JournalSession {
      throw ErreurRemote.reponseInattendue(code: 500)
    }
    func envoyerPrompt(_ identifiant: String, demande: DemandePrompt) async throws -> ReponsePrompt {
      throw ErreurRemote.reponseInattendue(code: 500)
    }
    func annuler(_ identifiant: String) async throws -> ReponseAnnulation {
      throw ErreurRemote.reponseInattendue(code: 500)
    }
  }
}

private func appareil(jeton: String = jetonEchange, portee: String = "lecture") -> AppareilAppaire {
  AppareilAppaire(protocole: 1, jeton: jeton, portee: portee, nom: "iPhone de test", creeLe: 1_700_000_000_000)
}

/// Un modèle sur des préférences jetables ET un gardien en mémoire.
///
/// `modeleDeTest()` ne suffit pas ici : son gardien par défaut écrit au
/// TROUSSEAU de la machine. Un test n'écrit pas un secret dans le trousseau de
/// quelqu'un d'autre.
@MainActor
private func modeleEtGardien(_ transport: TransportFactice? = nil) -> (ModeleApp, GardienEnMemoire) {
  let gardien = GardienEnMemoire()
  let modele =
    transport == nil
    ? ModeleApp(gardien: gardien, persistance: persistanceDeTest())
    : ModeleApp(gardien: gardien, persistance: persistanceDeTest(), transport: transport!.connexion())
  return (modele, gardien)
}

@MainActor
@Test("Un appairage par jeton remplit l'adresse ET le jeton")
func appairageParJeton() async {
  let (modele, gardien) = modeleEtGardien()

  #expect(await modele.appairer(chargeJeton))
  #expect(modele.adresse == "https://mac-mini-essai.exemple.test")
  #expect(modele.jetonSaisi == jetonAttendu)
  // LE JETON EST GARDÉ POUR CET HÔTE, pas dans un champ global : c'est la règle
  // « chaque machine a le sien », et l'appairage ne doit pas y déroger.
  #expect(gardien.lire(pour: IdentiteHote.cle("http://mac-mini-essai.exemple.test")) == jetonAttendu)
}

@MainActor
@Test("Un CODE est échangé, et c'est le jeton reçu qui est rangé")
func appairageParCode() async {
  let transport = TransportFactice(resultat: .success(appareil()))
  let (modele, gardien) = modeleEtGardien(transport)

  #expect(await modele.appairer(chargeCode))
  // L'ÉCHANGE A EU LIEU, avec le code et l'adresse de la charge utile — et un nom
  // d'appareil, sans lequel la liste des appareils n'aurait que des empreintes.
  #expect(transport.demandes.count == 1)
  #expect(transport.demandes.first?.code == codeAttendu)
  #expect(transport.demandes.first?.adresse == "https://mac-mini-essai.exemple.test")
  #expect(transport.demandes.first?.nom.isEmpty == false)

  // CE QUI EST RANGÉ EST LE JETON RENDU, JAMAIS LE CODE.
  #expect(modele.jetonSaisi == jetonEchange)
  #expect(modele.jetonSaisi != codeAttendu)
  #expect(gardien.lire(pour: IdentiteHote.cle("http://mac-mini-essai.exemple.test")) == jetonEchange)
}

@MainActor
@Test("Un échange refusé ne range RIEN, et dit pourquoi")
func echangeRefuse() async {
  let transport = TransportFactice(resultat: .failure(ErreurRemote.appairageRefuse(motif: ErreurRemote.motifCodeExpire, detail: nil)))
  let (modele, gardien) = modeleEtGardien(transport)
  modele.definirAdresse("http://machine-deja-choisie.exemple.test")
  modele.enregistrerJeton("JETONDEPRECEDENTE-machine-0000000000000000000000")
  let adresseAvant = modele.adresse

  #expect(await modele.appairer(chargeCode) == false)

  // RIEN N'A BOUGÉ : ni l'adresse, ni le jeton, ni le trousseau.
  #expect(modele.adresse == adresseAvant)
  #expect(modele.jetonSaisi == "JETONDEPRECEDENTE-machine-0000000000000000000000")
  #expect(gardien.lire(pour: IdentiteHote.cle("http://mac-mini-essai.exemple.test")) == nil)
  #expect(modele.erreur?.isEmpty == false)
}

@MainActor
@Test("Un hôte trop ancien le dit, au lieu de laisser croire à un mauvais code")
func hoteSansEchange() async {
  // DEUX CAUSES, DEUX REMÈDES : un code expiré se répare en redemandant un code
  // (sur le Mac) ; un plugin trop ancien se répare en mettant le plugin à jour.
  // Les confondre enverrait chercher un problème de code qui n'existe pas.
  let transport = TransportFactice(resultat: .failure(ErreurRemote.appairageNonSupporte))
  let (modele, _) = modeleEtGardien(transport)

  #expect(await modele.appairer(chargeCode) == false)
  let message = modele.erreur ?? ""
  #expect(message.isEmpty == false)
  #expect(message.contains("404") == false, "un message d'interface ne montre pas un code HTTP : \(message)")
}

@MainActor
@Test("Appairer une seconde machine ne touche pas au jeton de la première")
func jetonParHoteConserve() async {
  let (modele, gardien) = modeleEtGardien()
  let seconde = "dshremote://mac-mini-2.exemple.test/jeton/v1/AUTREJETONFICTIF-b-remplacer-000000000000000"

  #expect(await modele.appairer(chargeJeton))
  #expect(await modele.appairer(seconde))

  #expect(modele.adresse == "https://mac-mini-2.exemple.test")
  #expect(modele.jetonSaisi == "AUTREJETONFICTIF-b-remplacer-000000000000000")
  // LE PREMIER JETON RESTE CELUI DE LA PREMIÈRE MACHINE : l'appairage ne doit
  // pas écraser un secret par un autre. C'est `viser` qui recharge le bon.
  #expect(gardien.lire(pour: IdentiteHote.cle("http://mac-mini-essai.exemple.test")) == jetonAttendu)
}

@MainActor
@Test("Un appairage refusé ne change RIEN, et dit pourquoi")
func appairageRefuse() async {
  let (modele, gardien) = modeleEtGardien()
  modele.definirAdresse("http://machine-deja-choisie.exemple.test")
  modele.enregistrerJeton("JETONDEPRECEDENTE-machine-0000000000000000000000")
  let adresseAvant = modele.adresse

  // Une charge utile qui vise la BOUCLE LOCALE : le cas le plus fréquent d'un
  // lien recopié depuis un terminal.
  let local = "dshremote://127.0.0.1/jeton/v1/JETONFICTIF-a-remplacer-0000000000000000000"
  #expect(await modele.appairer(local) == false)

  // RIEN N'A BOUGÉ : ni l'adresse, ni le jeton. Un refus qui laisserait une
  // moitié appliquée enverrait le jeton d'une machine à une autre.
  #expect(modele.adresse == adresseAvant)
  #expect(modele.jetonSaisi == "JETONDEPRECEDENTE-machine-0000000000000000000000")
  #expect(gardien.lire(pour: IdentiteHote.cle("http://mac-mini-essai.exemple.test")) == nil)

  // ET LE MOTIF EST DIT, pas résumé en « échec » : c'est ce message que lit
  // l'utilisateur, et trois causes ne se réparent pas pareil.
  #expect(modele.erreur == Appairage.Motif.hoteLocal.message)
}

@MainActor
@Test("Un texte quelconque est refusé, et l'adresse reste vide")
func texteQuelconqueRefuse() async {
  let (modele, _) = modeleEtGardien()
  let adresseAvant = modele.adresse
  #expect(await modele.appairer("bonjour") == false)
  #expect(modele.adresse == adresseAvant)
  #expect(modele.erreur == Appairage.Motif.forme.message)
}

@MainActor
@Test("Le nom proposé à l'hôte est celui de l'appareil, et il est non vide")
func nomPropose() {
  // POURQUOI CE TEST. Depuis que chaque appareil a SON jeton, la liste des
  // appareils sert à en révoquer un : un nom vide la rendrait inutilisable.
  #expect(ModeleApp.nomDeCetAppareil.isEmpty == false)
}
