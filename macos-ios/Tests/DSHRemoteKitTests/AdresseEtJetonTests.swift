import Foundation
import Testing

@testable import DSHRemoteKit

// L'ADRESSE CONSEILLÉE, ET LE REMÈDE ÉCRIT.
//
// POURQUOI CES TESTS EXISTENT. Deux défauts de la même famille ont été trouvés
// par la revue : l'écran conseillait une adresse que le paquet ne pouvait PAS
// joindre (`http://` vers un nom de domaine, sans exception ATS — le cas de tout
// clone du dépôt), et le message d'un `401` envoyait recopier le jeton dans une
// feuille qui n'en contient plus aucun champ. Dans les deux cas, le remède
// prescrit menait à l'échec ou au vide.
//
// Ce qui se teste ici est la RÈGLE : ce que le paquet autorise se lit dans son
// Info.plist, et le conseil en découle. Les domaines employés sont fictifs.

/// L'exception telle que `Scripts/injecter-exception-ats.sh` l'écrit dans le
/// paquet construit : le domaine du tailnet, ses sous-domaines, et le nom court.
///
/// Une VALEUR CALCULÉE, et non une constante globale : `[String: Any]` n'est pas
/// `Sendable`, et une globale non sûre est refusée par le mode de concurrence
/// stricte de Swift 6 — à juste titre, puisqu'un dictionnaire peut être muté.
private var plistAvecException: [String: Any] {
  [
    "NSAppTransportSecurity": [
      "NSExceptionDomains": [
        "exemple.ts.net": [
          "NSExceptionAllowsInsecureHTTPLoads": true,
          "NSIncludesSubdomains": true,
        ],
        "exemple": ["NSExceptionAllowsInsecureHTTPLoads": true],
      ]
    ]
  ]
}

@Test("Le conseil d'iOS ne propose plus un nom en clair quand le paquet n'a pas d'exception")
func conseilSansException() {
  // LE DÉFAUT RÉPARÉ. Le champ affichait `http://mon-mac.mon-tailnet.ts.net` et
  // le pied de page le présentait comme le chemin normal. Un clone du dépôt n'a
  // pas d'exception ATS : l'adresse conseillée était donc exactement celle qui
  // échoue, et elle échouait sans que l'écran en dise la cause.
  let conseil = ConseilAdresse.pour(adresse: "", plist: nil, plateforme: .iOS)
  #expect(conseil.exemple.hasPrefix("https://"), "sans exception, seul HTTPS est joignable")
  #expect(conseil.aide.contains("ATS"))
  #expect(conseil.aide.contains("construire-app-ios.sh"), "le script qui pose l'exception est nommé")
}

@Test("Avec l'exception du tailnet, le conseil redevient du clair — et il le dit")
func conseilAvecException() {
  let conseil = ConseilAdresse.pour(adresse: "", plist: plistAvecException, plateforme: .iOS)
  #expect(conseil.exemple.hasPrefix("http://"))
  #expect(conseil.aide.contains("autorise le clair"))
}

@Test("Une adresse en clair que ce paquet refusera est annoncée AVANT l'essai")
func avertissementAvantEssai() {
  // L'avertissement ne remplace pas l'erreur de transport : il évite d'y aller.
  // `-1022` est le code exact que rend App Transport Security, et celui qui
  // envoie aujourd'hui chercher une panne réseau là où le refus est certain.
  let refuse = ConseilAdresse.pour(
    adresse: "http://mac-mini.exemple.ts.net", plist: nil, plateforme: .iOS)
  #expect(refuse.avertissement?.contains("-1022") == true)

  // CE QUI NE DOIT RIEN DÉCLENCHER : HTTPS est ce qu'ATS veut, et une IP
  // littérale en est exemptée. Avertir l'un ou l'autre ferait douter d'une
  // adresse qui marche.
  for adresse in [
    "https://mac-mini.exemple.ts.net", "http://100.101.102.103:3080", "http://127.0.0.1:3080",
    "http://localhost:3080",
  ] {
    #expect(
      ConseilAdresse.pour(adresse: adresse, plist: nil, plateforme: .iOS).avertissement == nil,
      "« \(adresse) » ne doit pas être annoncée comme refusée")
  }

  // Et l'exception, quand elle est là, fait taire l'avertissement.
  #expect(
    ConseilAdresse.pour(
      adresse: "http://mac-mini.exemple.ts.net", plist: plistAvecException, plateforme: .iOS
    ).avertissement == nil)
}

@Test("L'exception couvre le domaine, ses sous-domaines, et le nom court")
func porteeDeLException() {
  #expect(ExceptionATS.autoriseLeClair(vers: "exemple.ts.net", plistAvecException))
  #expect(ExceptionATS.autoriseLeClair(vers: "mac-mini.exemple.ts.net", plistAvecException))
  #expect(ExceptionATS.autoriseLeClair(vers: "exemple", plistAvecException))
  // L'appariement d'ATS est LITTÉRAL : un domaine qui se termine par le même
  // texte sans être un sous-domaine n'est PAS couvert. Sans cette borne, une
  // exception pour `exemple.ts.net` autoriserait `notreexemple.ts.net`.
  #expect(!ExceptionATS.autoriseLeClair(vers: "notreexemple.ts.net", plistAvecException))
  #expect(!ExceptionATS.autoriseLeClair(vers: "autre.ts.net", plistAvecException))
}

@Test("Une exception déclarée sans autorisation ne couvre rien")
func exceptionInoperante() {
  // LE PIRE DES CAS, ET IL A ÉTÉ MESURÉ : une exception PRÉSENTE dans le plist,
  // donc visible, mais sans `NSExceptionAllowsInsecureHTTPLoads` — elle ne
  // protège rien. La lire comme une autorisation ferait taire l'avertissement
  // qui, lui, était juste.
  let inoperante: [String: Any] = [
    "NSAppTransportSecurity": [
      "NSExceptionDomains": ["exemple.ts.net": ["NSIncludesSubdomains": true]]
    ]
  ]
  #expect(!ExceptionATS.autoriseLeClair(vers: "mac-mini.exemple.ts.net", inoperante))
  #expect(ExceptionATS.seraRefuse("http://mac-mini.exemple.ts.net", inoperante))
}

@Test("`NSAllowsArbitraryLoads` autorise tout, et il est lu comme tel")
func toutAutoriser() {
  // Les scripts du dépôt ne posent jamais ce drapeau — une exception ciblée vaut
  // mieux qu'une porte ouverte —, mais un paquet qui le porterait autorise
  // réellement le clair : le nier serait faux.
  let large: [String: Any] = ["NSAppTransportSecurity": ["NSAllowsArbitraryLoads": true]]
  #expect(ExceptionATS.autoriseLeClair(vers: "n-importe-quoi.ts.net", large))
  #expect(!ExceptionATS.seraRefuse("http://n-importe-quoi.ts.net", large))
}

@Test("L'hôte d'une adresse se lit avec ou sans protocole, avec ou sans port")
func lectureDeLHote() {
  #expect(ExceptionATS.hote("http://mac-mini.exemple.ts.net") == "mac-mini.exemple.ts.net")
  #expect(ExceptionATS.hote("mac-mini.exemple.ts.net:3080") == "mac-mini.exemple.ts.net")
  #expect(ExceptionATS.hote("https://mac-mini.exemple.ts.net/chemin") == "mac-mini.exemple.ts.net")
  #expect(ExceptionATS.hote("http://100.101.102.103:3080") == "100.101.102.103")
  #expect(ExceptionATS.hote("") == nil)
  #expect(ExceptionATS.hote("   ") == nil)
}

@Test("Un nom qualifié se distingue d'une IP littérale et de la boucle locale")
func nomsQualifies() {
  #expect(ExceptionATS.estUnNomQualifie("mac-mini.exemple.ts.net"))
  #expect(!ExceptionATS.estUnNomQualifie("100.101.102.103"))
  #expect(!ExceptionATS.estUnNomQualifie("127.0.0.1"))
  #expect(!ExceptionATS.estUnNomQualifie("localhost"))
  #expect(!ExceptionATS.estUnNomQualifie("macmini"))
}

@Test("Le HTTP clair vers une IP publique est un jeton exposé")
func clairPublic() {
  #expect(ExceptionATS.hoteEnClairExpose("8.8.8.8"))
  #expect(ExceptionATS.hoteEnClairExpose("100.128.0.1"))
  #expect(ExceptionATS.hoteEnClairExpose("172.32.0.1"))
  #expect(ExceptionATS.hoteEnClairExpose("2001:db8::1"))
  #expect(!ExceptionATS.hoteEnClairExpose("100.64.0.1"))
  #expect(!ExceptionATS.hoteEnClairExpose("100.127.255.255"))
  #expect(!ExceptionATS.hoteEnClairExpose("192.168.1.10"))
  #expect(!ExceptionATS.hoteEnClairExpose("10.1.2.3"))
  #expect(!ExceptionATS.hoteEnClairExpose("172.16.0.1"))
  #expect(!ExceptionATS.hoteEnClairExpose("127.0.0.1"))
  #expect(!ExceptionATS.hoteEnClairExpose("::1"))
  #expect(!ExceptionATS.hoteEnClairExpose("localhost"))
  #expect(!ExceptionATS.hoteEnClairExpose("mac-mini.exemple.ts.net"))

  #expect(throws: ErreurRemote.self) {
    _ = try RemoteClient(adresse: "http://8.8.8.8:3080", jeton: "jeton-de-test-suffisamment-long")
  }
  #expect(throws: Never.self) {
    _ = try RemoteClient(adresse: "http://100.64.1.2:3080", jeton: "jeton-de-test-suffisamment-long")
  }
  #expect(throws: Never.self) {
    _ = try RemoteClient(adresse: "http://8.8.8.8:3080", jeton: "")
  }
  #expect(throws: Never.self) {
    _ = try RemoteClient(adresse: "https://8.8.8.8", jeton: "jeton-de-test-suffisamment-long")
  }
  #expect(FluxSession(adresse: "http://8.8.8.8:3080", jeton: "jeton-de-test-suffisamment-long", identifiant: "session-aaa") == nil)
  #expect(FluxSession(adresse: "http://127.0.0.1:3080", jeton: "jeton-de-test-suffisamment-long", identifiant: "session-aaa") != nil)
}

@Test("Le remède d'un 401 mène à un champ qui existe vraiment")
func remedeDu401() {
  // LE DÉFAUT RÉPARÉ. Le message disait « collez-le dans Réglages » : or la
  // feuille Réglages ne contient plus AUCUN champ de jeton depuis que chaque
  // hôte a le sien. Le seul remède écrit pour un iPhone neuf menait à un écran
  // vide. Les deux endroits qui portent le champ sont donc nommés — et le test
  // empêche d'en réintroduire un troisième qui n'existerait pas.
  let texte = ErreurRemote.jetonRefuse.description
  #expect(!texte.contains("Réglages"), "les Réglages ne contiennent plus de champ de jeton")
  #expect(texte.contains("Jeton d'appareil"))
  #expect(texte.contains("Adresse"))
  // Le message reste utile : il dit la cause ET le geste.
  #expect(texte.contains("401"))
  #expect(texte.contains("harness"))
}
