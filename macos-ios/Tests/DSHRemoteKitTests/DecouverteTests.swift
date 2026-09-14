import Foundation
import Testing

@testable import DSHRemoteKit

// La charge utile ci-dessous est une COPIE de `tailscale status --json` observée
// sur la machine de développement, réduite aux champs lus. La tester ainsi, et
// non sur un exemple inventé, est ce qui permet d'attraper une dérive réelle de
// la part de Tailscale.

@Test("Un PC Windows est retenu, un iPhone NON — héberger DSH n'est pas tenir dans une poche")
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
        "node4": { "HostName": "iphone-de-test", "DNSName": "iphone-de-test.exemple.ts.net.", "OS": "iOS", "Online": true },
        "node5": { "HostName": "tablette-de-test", "DNSName": "tablette-de-test.exemple.ts.net.", "OS": "android", "Online": true },
        "node6": { "HostName": "ServeurLinux", "DNSName": "serveur-linux.exemple.ts.net.", "OS": "linux", "Online": true }
      }
    }
  """.data(using: .utf8)!

  let machines = DecouverteServeurs.analyser(json)

  // LA RÈGLE A CHANGÉ, ET ELLE ÉTAIT FAUSSE. Elle ne retenait que `macOS` :
  // « proposer un PC Windows ou un iPhone comme serveur DSH serait une promesse
  // que l'installation ne peut pas tenir ». Le propriétaire a relevé la
  // confusion : DSH est un harness Node, il tourne aussi sur Windows et sur
  // Linux — seule l'APPLICATION est macOS et iOS. Ce qui ne peut pas héberger
  // DSH, c'est iOS et Android, qui n'exécutent pas de processus.
  #expect(machines.count == 5)
  #expect(machines.contains { $0.nom == "PortableWindows" })
  #expect(machines.contains { $0.nom == "ServeurLinux" })
  #expect(!machines.contains { $0.nom == "iphone-de-test" })
  #expect(!machines.contains { $0.nom == "tablette-de-test" })

  // En ligne d'abord, puis par nom : c'est ce qui garde la liste stable d'un
  // affichage à l'autre, et la machine locale n'a aucune priorité.
  #expect(machines.prefix(3).allSatisfy { $0.enLigne })
  #expect(machines.suffix(2).allSatisfy { !$0.enLigne })
  #expect(machines[0].nom == "Bureau Mini")
  #expect(machines[1].nom == "Portable Un")
}

@Test("Joignables d'abord, puis les PRÊTES avant celles restant à configurer")
func ordreJoignablePuisPret() {
  // L'ordre demandé, dans cet ordre exact : les machines joignables passent avant
  // les éteintes, et parmi les joignables, celles qui SERVENT DSH passent avant
  // celles qui restent à configurer. La vignette « Ajouter » est rendue après la
  // liste : elle vient donc après les éteintes, sans entrer dans ce tri.
  let prete = ServeurMac(nom: "Zulu", nomDNS: "zulu.exemple.ts.net", enLigne: true)
  let aConfigurer = ServeurMac(nom: "Alpha", nomDNS: "alpha.exemple.ts.net", enLigne: true)
  let eteinte = ServeurMac(nom: "Bravo", nomDNS: "bravo.exemple.ts.net", enLigne: false)

  // Le nom de la machine prête passe APRÈS celui de la machine à configurer :
  // seule la sonde décide, et elle la fait remonter.
  #expect(
    DecouverteServeurs.ordonnerPourAffichage([aConfigurer, eteinte, prete]) { $0.id == prete.id }.map(\.nom)
      == ["Zulu", "Alpha", "Bravo"])

  // La JOIGNABILITÉ prime sur tout le reste : une machine éteinte reste derrière
  // une machine joignable qui ne sert pas encore DSH, même si une sonde ancienne
  // l'avait dite prête.
  #expect(
    DecouverteServeurs.ordonnerPourAffichage([eteinte, aConfigurer]) { $0.id == eteinte.id }.map(\.nom)
      == ["Alpha", "Bravo"])

  // Sans verdict — découverte locale, ou sonde encore en vol — il ne reste que la
  // joignabilité et le nom : c'est la règle d'origine, et elle est stable.
  #expect(
    DecouverteServeurs.ordonnerPourAffichage([aConfigurer, eteinte, prete]).map(\.nom)
      == ["Alpha", "Zulu", "Bravo"])
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

@Test("Un CLI qui échoue en code 0 ne doit PAS devenir « tailnet vide »")
func cliQuiEchoueEnCodeZero() throws {
  // LE DÉFAUT, MESURÉ ET VU À L'ÉCRAN. Lancé depuis une application ouverte par
  // le Finder, le CLI Tailscale écrit ceci sur **stdout** et sort avec le code
  // 0. Le prendre pour un succès faisait annoncer « aucun Mac macOS dans le
  // tailnet » — un mensonge sur l'état du tailnet — et arrêtait la boucle des
  // candidats avant celui qui répond.
  let sortieCLI = Data(
    """
    The Tailscale GUI failed to start: The operation couldn’t be completed. (Tailscale.CLIError error 3.)

    """.utf8)

  // L'analyse STRICTE refuse de conclure : ce n'est pas un état, c'est un échec.
  #expect(DecouverteServeurs.analyserEtat(sortieCLI) == nil)
  // Le contrat historique d'`analyser` est conservé (liste vide), mais c'est
  // désormais `analyserEtat` que la découverte emploie.
  #expect(DecouverteServeurs.analyser(sortieCLI).isEmpty)

  // Un JSON valide mais SANS `Self` ne dit rien non plus : un tailnet qui
  // répond porte toujours l'identité de la machine locale.
  #expect(DecouverteServeurs.analyserEtat(Data("{\"BackendState\":\"NoState\"}".utf8)) == nil)
  #expect(DecouverteServeurs.analyserEtat(Data("{}".utf8)) == nil)

  // Et un état réel reste accepté, y compris avec un seul Mac (soi-même).
  let valide = Data(
    """
    {"Self":{"HostName":"Portable Un","DNSName":"portable-un.exemple.ts.net.","OS":"macOS","Online":true}}
    """.utf8)
  #expect(try #require(DecouverteServeurs.analyserEtat(valide)).count == 1)
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
  // LE MÊME DOMAINE POUR LES DEUX MODÈLES, et c'est tout le test : deux
  // `modeleDeTest()` créeraient deux domaines distincts, et la relecture ne
  // prouverait rien. C'est ce qu'a révélé la correction de l'herméticité — le
  // test lisait auparavant le domaine PARTAGÉ de la suite.
  let persistance = persistanceDeTest()
  let modele = ModeleApp(persistance: persistance)
  modele.definirAdresse(adresseTemoin)

  let relu = ModeleApp(persistance: persistance)
  #expect(relu.adresse == adresseTemoin, "l'adresse écrite doit être relue au lancement suivant")

  // Et l'oubli efface VRAIMENT ce qui était mémorisé.
  //
  // L'ASSERTION PORTE SUR LA PERSISTANCE, PAS SUR LE MODÈLE, et c'est une
  // correction : après un oubli, un modèle neuf retombe sur son adresse par
  // défaut (`http://127.0.0.1:3080`, la boucle locale) — le formulaire n'est
  // jamais « vidé » au lancement. Asserter `modele.adresse.isEmpty` échouait donc
  // toujours, et le test ne prouvait rien de ce qu'il annonçait.
  relu.oublierServeur()
  #expect(persistance.lireAdresse().adresse.isEmpty)
  #expect(ModeleApp(persistance: persistance).adresse == "http://127.0.0.1:3080")
}

// ── Regroupement par espace de travail ────────────────────────────────────────
//
// Les charges utiles sont des copies de réponses réelles du plugin : c'est ce
// qui permet d'attraper une dérive de la part du serveur, et non de vérifier
// que le code s'accorde avec lui-même.

private func sessionDeTest(
  id: String, cwd: String?, titre: String, quand: Int, cree: Int = 1, profondeur: Int = 0, vivante: Bool = true
) -> SessionListee {
  let cwdJSON = cwd.map { "\"cwd\":\"\($0)\"," } ?? ""
  let json = """
    {"protocole":1,"total":1,"sessions":[
      {"projet":"--x--","dossier":"/d","fichier":"/f","octets":100,"modifieLe":1,"vivante":\(vivante),
       "id":"\(id)",\(cwdJSON)"creeLe":\(cree),"preset":"standard","profondeurDelegation":\(profondeur),
       "seme":false,"titre":"\(titre)","dernierEvenementLe":\(quand),"dernierSeq":1,
       "nbEnregistrements":1,"tronque":false}]}
    """.data(using: .utf8)!
  return try! JSONDecoder().decode(ListeSessions.self, from: json).sessions[0]
}

@Test("Les espaces sont classés par CRÉATION, les sessions par ACTIVITÉ")
func trisDistincts() {
  // LES DEUX TRIS NE SUIVENT PAS LA MÊME DATE — c'est la règle de l'interface
  // web, lue dans le service hôte (`newestAt`) : un espace est classé par la
  // création de sa session la plus récente, une session par sa dernière
  // activité. Trier les espaces par activité faisait remonter l'arbre à chaque
  // message reçu, et déplaçait sous le doigt ce qu'on visait.
  let sessions = [
    // Espace ANCIEN (créé t=1000) mais très actif (dernier événement t=9000).
    sessionDeTest(id: "ancien", cwd: "/tmp/ancien", titre: "Ancien", quand: 9_000, cree: 1_000),
    // Espace RÉCENT (créé t=8000), moins actif (t=8500) : il doit passer DEVANT.
    sessionDeTest(id: "recent", cwd: "/tmp/recent", titre: "Récent", quand: 8_500, cree: 8_000),
    // Deuxième session du même espace récent, créée avant mais plus active.
    sessionDeTest(id: "recent-2", cwd: "/tmp/recent", titre: "Récent 2", quand: 9_500, cree: 7_000),
  ]
  let espaces = Regroupement.espaces(sessions)

  #expect(espaces.map(\.nom) == ["recent", "ancien"])
  #expect(espaces[1].nbSessions == 1)
  // Dans un espace, c'est bien l'ACTIVITÉ qui classe : la plus récente d'abord.
  #expect(espaces[0].sessions.map(\.id) == ["recent-2", "recent"])
}

@Test("Deux espaces créés au même instant gardent un ordre stable")
func departageStable() {
  // Sans départage, deux espaces de même date pourraient s'échanger d'un
  // rafraîchissement à l'autre : l'arbre « sauterait » sans raison visible.
  let sessions = [
    sessionDeTest(id: "b", cwd: "/tmp/projet-b", titre: "B", quand: 100, cree: 5_000),
    sessionDeTest(id: "a", cwd: "/tmp/projet-a", titre: "A", quand: 200, cree: 5_000),
  ]
  #expect(Regroupement.espaces(sessions).map(\.nom) == ["projet-a", "projet-b"])
}

@Test("Une session sans date de création n'est pas traitée comme très ancienne")
func creationManquante() {
  // Un journal muet sur `creeLe` ne doit pas être relégué en 1970 : on retombe
  // sur son activité, qui est un fait connu.
  let sansCreation = sessionDeTest(id: "muet", cwd: "/tmp/muet", titre: "Muet", quand: 9_000, cree: 0)
  let ancienne = sessionDeTest(id: "vieux", cwd: "/tmp/vieux", titre: "Vieux", quand: 1_000, cree: 1_000)
  #expect(Regroupement.espaces([sansCreation, ancienne]).map(\.nom) == ["muet", "vieux"])
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
