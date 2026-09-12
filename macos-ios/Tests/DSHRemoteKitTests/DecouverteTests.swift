import Foundation
import Testing

@testable import DSHRemoteKit

// La charge utile ci-dessous est une COPIE de `tailscale status --json` observée
// sur la machine de développement, réduite aux champs lus. La tester ainsi, et
// non sur un exemple inventé, est ce qui permet d'attraper une dérive réelle de
// la part de Tailscale.

@Test("Les Macs du tailnet sont retenus, les autres systèmes écartés")
func analyseTailnet() throws {
  let json = """
    {
      "Self": {
        "HostName": "Portable Un",
        "DNSName": "portable-un.exemple.ts.net.",
        "OS": "macOS",
        "Online": true
      },
      "Peer": {
        "node1": { "HostName": "Bureau Mini", "DNSName": "bureau-mini.exemple.ts.net.", "OS": "macOS", "Online": true },
        "node2": { "HostName": "Portable Deux", "DNSName": "portable-deux.exemple.ts.net.", "OS": "macOS", "Online": false },
        "node3": { "HostName": "PortableWindows", "DNSName": "portable-windows.exemple.ts.net.", "OS": "windows", "Online": false },
        "node4": { "HostName": "iphone-de-test", "DNSName": "iphone-de-test.exemple.ts.net.", "OS": "iOS", "Online": true }
      }
    }
  """.data(using: .utf8)!

  let macs = DecouverteServeurs.analyser(json)

  // Trois macOS (soi-même inclus), et NI le PC Windows NI l'iPhone : on ne
  // propose que des machines capables de faire tourner le harness.
  #expect(macs.count == 3)
  #expect(!macs.contains { $0.nom == "PortableWindows" })
  #expect(!macs.contains { $0.nom == "iphone-de-test" })

  // En ligne d'abord, puis par nom : « Bureau Mini » précède « Portable Un ».
  #expect(macs[0].nom == "Bureau Mini")
  #expect(macs[1].nom == "Portable Un")
  #expect(macs[2].nom == "Portable Deux")
  #expect(macs[2].enLigne == false)
}

@Test("Le point final du nom DNS est retiré : l'adresse doit être utilisable telle quelle")
func adresseUtilisable() throws {
  let json = """
    {"Self":{"HostName":"Bureau Mini","DNSName":"bureau-mini.exemple.ts.net.","OS":"macOS","Online":true}}
  """.data(using: .utf8)!

  let mac = try #require(DecouverteServeurs.analyser(json).first)
  #expect(mac.nomDNS == "bureau-mini.exemple.ts.net")
  #expect(!mac.nomDNS.hasSuffix("."))
  // `tailscale serve` publie sur le port 80 du nom MagicDNS : pas de port.
  #expect(mac.adresse == "http://bureau-mini.exemple.ts.net")
}

@Test("L'icône suit le nom de la machine")
func icones() {
  // Les noms « MacBook Air » et « MacMini » sont ceux que macOS donne aux
  // machines : c'est bien eux que la détection doit reconnaître, même si les
  // fixtures d'analyse ci-dessus emploient des noms neutres.
  #expect(ServeurMac(nom: "MacBook Air de Quelqu'un", nomDNS: "a", enLigne: true).symbole == "macbook")
  #expect(ServeurMac(nom: "MacMini", nomDNS: "b", enLigne: true).symbole == "macmini")
  #expect(ServeurMac(nom: "MacBook Pro de Quelqu'un", nomDNS: "c", enLigne: false).symbole == "macbook")
  #expect(ServeurMac(nom: "iMac de la cuisine", nomDNS: "d", enLigne: true).symbole == "desktopcomputer")
  // Une machine renommée ne doit pas produire d'icône vide.
  #expect(ServeurMac(nom: "bureau", nomDNS: "e", enLigne: true).symbole == "desktopcomputer")
}

#if canImport(AppKit)
  import AppKit

  @Test("Chaque icône rendue est un symbole SF qui existe vraiment")
  func iconesExistantes() {
    // POURQUOI CE TEST EXISTE. Une capture d'écran de l'application sur iPhone a
    // montré des lignes SANS icône, pour un MacBook Air et un MacBook Pro.
    // Cause : `macbook.air` et `macbook.pro` ne sont pas des symboles SF, et
    // `Image(systemName:)` ne signale rien — il n'affiche rien. Le repli
    // générique n'était jamais atteint puisqu'un nom était bien rendu. Un test
    // qui se contente de comparer des chaînes ne peut pas voir ça : celui-ci
    // interroge le catalogue de la plateforme.
    let noms = [
      "MacBook Air de Quelqu'un", "MacBook Pro de Quelqu'un", "MacBook", "MacMini",
      "Mac mini de la maison", "MacStudio", "iMac de la cuisine", "bureau",
      "http://macbook-x.exemple.ts.net", "http://mac-mini.exemple.ts.net",
    ]
    for nom in noms {
      let symbole = ServeurMac(nom: nom, nomDNS: "", enLigne: true).symbole
      #expect(
        NSImage(systemSymbolName: symbole, accessibilityDescription: nil) != nil,
        "« \(nom) » rend « \(symbole) », qui n'existe pas dans SF Symbols : la ligne s'afficherait sans icône")
    }
  }
#endif

@Test("Le type de machine se déduit du nom, y compris depuis une adresse")
func iconeDepuisAdresse() {
  // Depuis une adresse saisie à la main, on n'a que le nom d'hôte. Les
  // séparateurs doivent être neutralisés, sinon un Mac mini s'afficherait en
  // machine générique.
  #expect(ServeurMac(nom: "http://macmini.exemple.ts.net", nomDNS: "", enLigne: true).symbole == "macmini")
  #expect(ServeurMac(nom: "http://mac-mini.exemple.ts.net", nomDNS: "", enLigne: true).symbole == "macmini")
  #expect(ServeurMac(nom: "Mac mini de la maison", nomDNS: "", enLigne: true).symbole == "macmini")
  // La famille « macbook » est reconnue sous sa forme à tirets, sans avoir à
  // écrire le nom d'une machine réelle dans un test.
  #expect(ServeurMac(nom: "http://macbook-x.exemple.ts.net", nomDNS: "", enLigne: true).symbole == "macbook")
  #expect(ServeurMac(nom: "http://mac-studio.exemple.ts.net", nomDNS: "", enLigne: true).symbole == "macstudio")
  // Repli sûr : jamais d'icône vide, même pour un nom sans rapport.
  #expect(ServeurMac(nom: "http://bureau.exemple.ts.net", nomDNS: "", enLigne: true).symbole == "desktopcomputer")
}

@Test("Une sortie illisible ne fait pas échouer la découverte")
func sortieIllisible() {
  #expect(DecouverteServeurs.analyser(Data("pas du json".utf8)).isEmpty)
  #expect(DecouverteServeurs.analyser(Data()).isEmpty)
  // Objet valide mais sans les champs attendus.
  #expect(DecouverteServeurs.analyser(Data("{\"Peer\":{}}".utf8)).isEmpty)
}

@MainActor
@Test("L'adresse est mémorisée dès qu'elle change, pas seulement après succès")
func memorisationAdresse() {
  // Le défaut corrigé : l'adresse n'était enregistrée que par `connecter()`,
  // donc une tentative ÉCHOUÉE ne laissait aucune trace — et c'est précisément
  // quand la connexion échoue qu'on veut retrouver son adresse.
  //
  // On teste le contrat réel du modèle, sans réseau : `definirAdresse` doit
  // écrire, et un modèle neuf doit relire ce qui a été écrit.
  let adresseTemoin = "temoin-memorisation.exemple.ts.net"
  let modele = ModeleApp()
  modele.definirAdresse(adresseTemoin)

  let relu = ModeleApp()
  #expect(relu.adresse == adresseTemoin, "l'adresse écrite doit être relue au lancement suivant")

  // Nettoyage : on ne laisse pas une adresse de test dans les préférences.
  relu.oublierServeur()
  #expect(ModeleApp().adresse.isEmpty || ModeleApp().adresse != adresseTemoin)
}

// ── Regroupement par espace de travail ────────────────────────────────────────
//
// Les charges utiles sont des copies de réponses réelles du plugin : c'est ce
// qui permet d'attraper une dérive de la part du serveur, et non de vérifier
// que le code s'accorde avec lui-même.

private func sessionDeTest(
  id: String, cwd: String?, titre: String, quand: Int, profondeur: Int = 0, vivante: Bool = true
) -> SessionListee {
  let cwdJSON = cwd.map { "\"cwd\":\"\($0)\"," } ?? ""
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":100,"modifieLe":1,"vivante":\(vivante),
       "id":"\(id)",\(cwdJSON)"creeLe":1,"preset":"standard","profondeurDelegation":\(profondeur),
       "seme":false,"titre":"\(titre)","dernierEvenementLe":\(quand),"dernierSeq":1,
       "nbEnregistrements":1,"tronque":false}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@Test("Les sessions sont groupées par espace de travail, le plus récent d'abord")
func groupementParEspace() {
  let sessions = [
    sessionDeTest(id: "a", cwd: "/tmp/projet-un", titre: "A", quand: 1_000),
    sessionDeTest(id: "b", cwd: "/tmp/projet-deux", titre: "B", quand: 9_000),
    sessionDeTest(id: "c", cwd: "/tmp/projet-un", titre: "C", quand: 5_000),
  ]
  let espaces = Regroupement.espaces(sessions)

  #expect(espaces.count == 2)
  // « projet-deux » est le plus récemment actif : il passe en tête.
  #expect(espaces[0].nom == "projet-deux")
  #expect(espaces[1].nom == "projet-un")
  #expect(espaces[1].nbSessions == 2)
  // Dans un espace, la session la plus récente d'abord.
  #expect(espaces[1].sessions.map(\.id) == ["c", "a"])
}

@Test("Le nom d'espace vient de cwd, pas du dossier de projet encodé")
func nomDepuisCwd() {
  // DSH encode les chemins en remplaçant « / » par « - » : le dossier ne permet
  // donc pas de distinguer « dsh-plugins » de « dsh/plugins ». `cwd` fait foi.
  let session = sessionDeTest(id: "a", cwd: "/tmp/atelier/dsh-plugins", titre: "A", quand: 1)
  let (nom, chemin) = Regroupement.nomEspace(session)
  #expect(nom == "dsh-plugins")
  #expect(chemin == "/tmp/atelier/dsh-plugins")

  // Repli quand cwd manque : on ne doit jamais rendre un libellé vide.
  let sansCwd = sessionDeTest(id: "b", cwd: nil, titre: "B", quand: 1)
  #expect(!Regroupement.nomEspace(sansCwd).nom.isEmpty)
}

@Test("Les sous-agents sont identifiés et ne comptent pas comme sessions racines")
func sousAgents() {
  let sessions = [
    sessionDeTest(id: "racine", cwd: "/tmp/p", titre: "Racine", quand: 5_000, profondeur: 0),
    sessionDeTest(id: "enfant", cwd: "/tmp/p", titre: "Enfant", quand: 6_000, profondeur: 1),
  ]
  let espace = Regroupement.espaces(sessions)[0]
  #expect(espace.nbSessions == 2)
  #expect(Regroupement.estSousAgent(espace.sessions.first { $0.id == "enfant" }!) == true)
  #expect(Regroupement.estSousAgent(espace.sessions.first { $0.id == "racine" }!) == false)
  // Un sous-agent n'a pas lui-même de sous-agents à afficher.
  #expect(Regroupement.sousAgents(de: espace.sessions.first { $0.id == "enfant" }!, dans: espace).isEmpty)
}

@Test("L'âge s'écrit en unités courtes, comme dans l'interface web")
func ageLisible() {
  let maintenant = Date(timeIntervalSince1970: 10_000_000)
  // Sans nombres magiques : on exprime l'écart en secondes, et la conversion en
  // millisecondes est faite par le test lui-même. Deux erreurs d'arithmétique
  // m'ont déjà fait écrire ici des valeurs fausses — l'intention doit être
  // lisible à la place.
  func age(_ ecartEnSecondes: Double) -> String {
    let horodatage = Int((maintenant.timeIntervalSince1970 - ecartEnSecondes) * 1000)
    return AgeLisible.texte(horodatage, maintenant: maintenant)
  }
  #expect(age(0) == "à l'instant")
  #expect(age(30) == "30s")
  #expect(age(5 * 60) == "5min")
  #expect(age(60 * 60) == "1h")
  #expect(age(24 * 60 * 60) == "1j")
  #expect(age(3 * 24 * 60 * 60) == "3j")
  // Une date absente ne doit pas produire de texte trompeur.
  #expect(AgeLisible.texte(nil, maintenant: maintenant) == "")
  #expect(AgeLisible.texte(0, maintenant: maintenant) == "")
}
