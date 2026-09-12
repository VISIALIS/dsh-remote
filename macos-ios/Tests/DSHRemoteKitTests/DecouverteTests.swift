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
  #expect(ServeurMac(nom: "MacBook Air de Quelqu'un", nomDNS: "a", enLigne: true).symbole == "macbook.air")
  #expect(ServeurMac(nom: "MacMini", nomDNS: "b", enLigne: true).symbole == "macmini")
  #expect(ServeurMac(nom: "MacBook Pro de Quelqu'un", nomDNS: "c", enLigne: false).symbole == "macbook.pro")
  #expect(ServeurMac(nom: "iMac de la cuisine", nomDNS: "d", enLigne: true).symbole == "desktopcomputer")
  // Une machine renommée ne doit pas produire d'icône vide.
  #expect(ServeurMac(nom: "bureau", nomDNS: "e", enLigne: true).symbole == "desktopcomputer")
}

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
