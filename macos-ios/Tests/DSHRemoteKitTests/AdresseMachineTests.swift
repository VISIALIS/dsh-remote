import Foundation
import Testing

@testable import DSHRemoteKit

// L'ADRESSE À VISER : CE QUE LE PAQUET AUTORISE, ET CE QUE L'HÔTE ANNONCE.
//
// POURQUOI CE FICHIER EXISTE. Trois endroits fabriquaient une adresse en écrivant
// `"http://" + hote` — le QR d'appairage, la liste des machines découvertes, la
// saisie manuelle. Or App Transport Security refuse le clair vers un nom
// qualifié, et il ne l'autorise que si le paquet porte une exception posée depuis
// un fichier local absent de tout clone. Conséquence mesurée, et c'était le plus
// gros obstacle à la distribution : un clone se construisait sans erreur et
// refusait tout le tailnet en `-1022`, appairage compris.
//
// LA RÈGLE EST DONC UNE LECTURE, PAS UNE DÉDUCTION : on interroge l'Info.plist du
// paquet. C'est ce qui rend ces tests possibles — ils donnent le plist qu'ils
// veulent, et le paquet de test, lui, n'en a aucun.

@Test("Sans exception ATS, un nom qualifié passe en HTTPS ; une IP littérale reste en clair")
func adresseSelonLePaquet() {
  // 1. LE CAS DU CLONE : aucune exception, donc le clair est refusé vers un nom.
  #expect(
    AdresseMachine.pour(hote: "mac-mini.exemple.ts.net", plist: nil)
      == "https://mac-mini.exemple.ts.net")
  // 2. LE CAS DU PAQUET CONSTRUIT PAR LE SCRIPT : l'exception autorise le clair.
  #expect(
    AdresseMachine.pour(hote: "mac-mini.exemple.ts.net", plist: plistAvecException(pour: "exemple.ts.net"))
      == "http://mac-mini.exemple.ts.net")
  // 3. ATS NE CONCERNE PAS LES IP LITTÉRALES NI LA BOUCLE LOCALE : elles restent en
  //    clair, et c'est mesuré (`http://100.x.y.z:3080` répond, `-1022` ne s'y
  //    applique pas). Les faire passer en HTTPS coûterait un certificat pour rien.
  #expect(AdresseMachine.pour(hote: "100.101.102.103:3080", plist: nil) == "http://100.101.102.103:3080")
  #expect(AdresseMachine.pour(hote: "127.0.0.1:3080", plist: nil) == "http://127.0.0.1:3080")
  #expect(AdresseMachine.pour(hote: "localhost:3080", plist: nil) == "http://localhost:3080")
}

@Test("Une adresse vide ne devient pas « http:// », et un schéma déjà là n'est pas redoublé")
func adresseSansInvention() {
  #expect(AdresseMachine.pour(hote: "", plist: nil) == "")
  #expect(AdresseMachine.pour(hote: "   ", plist: nil) == "")
  #expect(AdresseMachine.pour(hote: "https://mac.exemple.ts.net", plist: nil) == "https://mac.exemple.ts.net")
  #expect(AdresseMachine.pour(hote: "http://mac.exemple.ts.net", plist: nil) == "http://mac.exemple.ts.net")
}

@Test("Le transport ANNONCÉ par l'hôte gagne — sauf si le paquet ne peut pas le suivre")
func transportAnnonce() {
  let avecException = plistAvecException(pour: "exemple.ts.net")
  // Un hôte publié en HTTPS : le paquet suit, qu'il ait une exception ou non.
  #expect(
    AdresseMachine.pour(hote: "mac.exemple.ts.net", schemaAnnonce: "https", plist: nil)
      == "https://mac.exemple.ts.net")
  #expect(
    AdresseMachine.pour(hote: "mac.exemple.ts.net", schemaAnnonce: "https", plist: avecException)
      == "https://mac.exemple.ts.net")
  // Un hôte publié en clair, dans un paquet qui REFUSE le clair : la règle la plus
  // sévère l'emporte, sinon l'adresse serait refusée par ATS avant de partir.
  #expect(
    AdresseMachine.pour(hote: "mac.exemple.ts.net", schemaAnnonce: "http", plist: nil)
      == "https://mac.exemple.ts.net")
  // Et dans un paquet qui l'autorise, l'annonce est suivie telle quelle.
  #expect(
    AdresseMachine.pour(hote: "mac.exemple.ts.net", schemaAnnonce: "http", plist: avecException)
      == "http://mac.exemple.ts.net")
}

@Test("L'identité d'un hôte est son NOM : le schéma n'en fait pas partie")
func identiteSansTransport() {
  // POURQUOI C'EST LA RÈGLE, ET CE QU'ELLE ÉVITE. La clé portait l'adresse
  // complète : la même machine publiée en HTTPS devenait une AUTRE machine, donc
  // le jeton rangé pour la forme en clair était introuvable et la machine jointe
  // n'était plus reconnue — pour un simple changement de transport.
  #expect(IdentiteHote.cle("http://mac.exemple.ts.net") == IdentiteHote.cle("https://mac.exemple.ts.net"))
  #expect(IdentiteHote.cle("mac.exemple.ts.net") == "mac.exemple.ts.net")
  #expect(IdentiteHote.cle("http://mac.exemple.ts.net/") == "mac.exemple.ts.net")
  // LE PORT RESTE : deux services d'une même machine sont deux hôtes distincts.
  #expect(IdentiteHote.cle("http://mac.exemple.ts.net:3080") == "mac.exemple.ts.net:3080")
  #expect(IdentiteHote.cle("100.101.102.103:3080") == "100.101.102.103:3080")
}

@MainActor
@Test("Un jeton rangé sous l'ANCIENNE clé est retrouvé, réécrit, et l'ancienne est effacée")
func migrationDeLaCleDHote() {
  // LE DÉFAUT QUE CE TEST FIXE. Les clés portaient le schéma (« http://… »). Les
  // changer sans rien lire aurait fait dire « aucun jeton » à un appareil
  // parfaitement appairé, pour une mise à jour du logiciel seul. On retrouve donc
  // l'ancienne entrée, on la réécrit sous la clé neuve, et on efface l'ancienne :
  // la migration ne demande aucun geste, et aucun secret ne reste en double.
  let jeton = String(repeating: "J", count: 43)
  let gardien = GardienEnMemoire()
  gardien.ecrire(jeton, pour: "http://mac.exemple.test")

  let modele = ModeleApp(gardien: gardien, persistance: persistanceDeTest())
  modele.definirAdresse("https://mac.exemple.test")

  #expect(modele.jetonDeLaCible() == jeton, "un jeton rangé avant la mise à jour doit être retrouvé")
  #expect(gardien.lire(pour: "mac.exemple.test") == jeton, "il est réécrit sous la clé neuve")
  #expect(gardien.lire(pour: "http://mac.exemple.test") == nil, "l'ancienne entrée est effacée")

  // Et l'effacement explicite ne laisse RIEN derrière lui, même si la migration
  // n'a pas eu lieu (jeton absent, réglage oublié).
  gardien.ecrire(jeton, pour: "http://autre.exemple.test")
  modele.effacerJeton(pour: "https://autre.exemple.test")
  #expect(gardien.lire(pour: "autre.exemple.test") == nil)
  #expect(gardien.lire(pour: "http://autre.exemple.test") == nil, "l'effacement doit vraiment tout effacer")
}

@MainActor
@Test("Une adresse en clair restaurée des préférences est relevée en HTTPS")
func preferenceRestaureeSuitLaRegle() {
  // POURQUOI CE TEST. L'adresse est mémorisée à la frappe, donc une préférence
  // écrite par une version antérieure porte « http://… ». La restaurer telle
  // quelle ferait échouer chaque connexion en `-1022` dans un paquet sans
  // exception — un refus certain, annoncé comme une panne de réseau.
  let persistance = persistanceDeTest()
  let premier = ModeleApp(persistance: persistance)
  premier.definirAdresse("http://temoin.exemple.ts.net")

  // Ce qui est écrit est déjà relevé…
  #expect(premier.adresse == "https://temoin.exemple.ts.net")
  // …et ce qui est RELU l'est aussi, y compris une valeur en clair écrite à la main.
  persistance.memoriserAdresse("http://ecrit-a-la-main.exemple.ts.net", nom: nil)
  let relu = ModeleApp(persistance: persistance)
  #expect(relu.adresse == "https://ecrit-a-la-main.exemple.ts.net")
}
