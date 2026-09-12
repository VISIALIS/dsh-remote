import Foundation
import Testing

@testable import DSHRemoteKit

// Ces tests ne touchent pas le réseau : ils vérifient que le client décode
// exactement ce que le plugin hôte produit. Les charges utiles sont des COPIES
// de réponses réelles observées au `curl`, pas des exemples inventés — c'est ce
// qui donne à ces tests le pouvoir d'attraper une dérive du protocole.

@Test("Une liste de sessions réelle se décode")
func decodeListe() throws {
  let json = """
    {"protocole":1,"racine":"/tmp/exemple/.dsh/sessions","total":2,"sessions":[
      {"projet":"--Users-x-Projets-dsh-plugins--","cwdIndicatif":"/tmp/exemple/Projets/dsh/plugins",
       "dossier":"/tmp/exemple/.dsh/sessions/--Users-x--/session-1","fichier":"/tmp/exemple/.dsh/sessions/--Users-x--/session-1/session.v3.jsonl.zstd",
       "octets":375808,"modifieLe":1789219944088.5,"vivante":true,
       "id":"session-83727ed7","cwd":"/tmp/exemple/Projets/dsh-plugins","creeLe":1789059396815,
       "preset":"standard","profondeurDelegation":0,"seme":false,
       "titre":"Application iOS Swift pour DeepSeek","dernierEvenementLe":1789219900000,
       "dernierSeq":405,"nbEnregistrements":406,"tronque":false},
      {"projet":"--Users-x--","cwdIndicatif":"/Users/x","dossier":"/d","fichier":"/f",
       "octets":1024,"modifieLe":1.0,"vivante":false,"illisible":"lecture impossible"}
    ]}
    """.data(using: .utf8)!

  let liste = try JSONDecoder().decode(ListeSessions.self, from: json)
  #expect(liste.protocole == 1)
  #expect(liste.total == 2)
  #expect(liste.sessions.count == 2)

  let premiere = liste.sessions[0]
  #expect(premiere.id == "session-83727ed7")
  #expect(premiere.titreAffiche == "Application iOS Swift pour DeepSeek")
  #expect(premiere.vivante == true)
  #expect(premiere.resume.nbEnregistrements == 406)
  #expect(premiere.resume.cwd == "/tmp/exemple/Projets/dsh-plugins")
  #expect(premiere.resume.preset == "standard")
  #expect(premiere.resume.seme == false)
  // Ces deux champs sont ceux qui ont révélé la dérive camelCase/snake_case :
  // ils restent donc explicitement vérifiés.
  #expect(premiere.resume.nbEnregistrements == 406)
  #expect(premiere.resume.dernierEvenementLe == 1789219900000)
  #expect(premiere.resume.dernierSeq == 405)
  #expect(premiere.resume.creeLe == 1789059396815)

  // Le résumé est aplati dans l'objet : il doit se décoder depuis le MÊME
  // conteneur, sans imbrication.
  let seconde = liste.sessions[1]
  #expect(seconde.resume.id == nil)
  #expect(seconde.titreAffiche == "(sans titre)")
  #expect(seconde.illisible == "lecture impossible")
}

@Test("Un journal réel se décode et les clés camelCase sont respectées")
func decodeJournal() throws {
  let json = """
    {"protocole":1,
     "session":{"id":"session-1","cwd":"/tmp","creeLe":1789059396815,"preset":"standard",
                "profondeurDelegation":0,"seme":false,"titre":"T","dernierEvenementLe":1789219900000,
                "dernierSeq":405,"nbEnregistrements":406,"tronque":false,
                "projet":"--p--","octets":375808,"modifieLe":1.0,"vivante":true},
     "depuis":0,"limite":3,"total":407,"tronque":false,
     "enregistrements":[{"type":"session","version":3,"id":"session-1","createdAt":1789059396815},
                        {"type":"permission/preset","seq":0,"time":1789059396822},
                        {"type":"sandbox/mode","seq":1,"time":1789059396822}]}
    """.data(using: .utf8)!

  let journal = try JSONDecoder().decode(JournalSession.self, from: json)
  #expect(journal.protocole == 1)
  #expect(journal.total == 407)
  #expect(journal.enregistrements.count == 3)
  #expect(journal.enregistrements[0].type == "session")
  #expect(journal.enregistrements[1].seq == 0)
  #expect(journal.session.titre == "T")
  #expect(journal.session.creeLe == 1789059396815)
}

@Test("Une adresse sans protocole est complétée, pas refusée")
func normalisationAdresse() {
  // Le cas réel : un nom d'hôte recopié depuis `tailscale serve status`, sans
  // « http:// ». Le refuser revenait à rejeter une saisie correcte.
  #expect(RemoteClient.normaliser("macmini.exemple.ts.net") == "http://macmini.exemple.ts.net")
  #expect(RemoteClient.normaliser("  macmini.exemple.ts.net  ") == "http://macmini.exemple.ts.net")
  // Un schéma déjà présent n'est jamais réécrit.
  #expect(RemoteClient.normaliser("https://macmini.exemple.ts.net") == "https://macmini.exemple.ts.net")
  #expect(RemoteClient.normaliser("http://127.0.0.1:3080") == "http://127.0.0.1:3080")
  #expect(RemoteClient.normaliser("") == "")

  // Et le client doit accepter la forme courte.
  #expect(throws: Never.self) {
    _ = try RemoteClient(adresse: "macmini.exemple.ts.net", jeton: "jeton-de-test-suffisamment-long")
  }
}

@Test("Une adresse invalide est refusée avant tout accès réseau")
func adresseInvalide() {
  #expect(throws: ErreurRemote.self) {
    _ = try RemoteClient(adresse: "pas une adresse", jeton: "x")
  }
  #expect(throws: ErreurRemote.self) {
    _ = try RemoteClient(adresse: "ftp://exemple.fr", jeton: "x")
  }
}

@Test("Les erreurs disent quoi faire, pas seulement ce qui a échoué")
func messagesDErreur() {
  #expect(String(describing: ErreurRemote.jetonRefuse).contains("401"))
  #expect(String(describing: ErreurRemote.origineRefusee).contains("Origin"))
  let version = String(describing: ErreurRemote.versionIncompatible(recue: 2, supportee: 1))
  #expect(version.contains("2"))
  #expect(version.contains("1"))
}
