import Foundation
import Testing

@testable import DSHRemoteKit

// LE COFFRE ET L'EMPREINTE — deux pièces déplacées hors du modèle, et qui
// n'étaient éprouvées par RIEN.
//
// La première porte une règle de sécurité : `~/.dsh/.credentials.yaml` contient
// au moins deux secrets de 43 caractères, et prendre le premier venu ramassait le
// secret qui signe les cookies de session du navigateur — un jeton d'apparence
// valide, refusé en `401`. La seconde décide de ce qui peut être ÉCRIT d'un jeton
// dans un fichier de diagnostic.

/// Un coffre factice, avec les DEUX secrets qu'il contient en vrai.
private let coffre = """
  dsh-remote/device-token:
    token: \(String(repeating: "a", count: 43))
  client-connection/browser-session:
    token: \(String(repeating: "b", count: 43))
  """

@Test("Le coffre donne le jeton du plugin, PAS le secret de session")
func coffreChoisitLeBonSecret() {
  let jeton = CoffreDuHarness.jetonDuCoffre(coffre)
  #expect(jeton == String(repeating: "a", count: 43))
  // Le piège mesuré : la première ligne « token » du fichier est celle du secret
  // de signature des cookies. La prendre donnait un jeton de 43 caractères que le
  // serveur refusait — et rien ne disait pourquoi.
  #expect(jeton != String(repeating: "b", count: 43))
}

@Test("Un coffre sans l'enregistrement du plugin ne rend rien")
func coffreSansEnregistrement() {
  let autre = """
    client-connection/browser-session:
      token: \(String(repeating: "b", count: 43))
    """
  // Rien plutôt qu'un secret qui n'est pas le bon : l'application dira « aucun
  // jeton », ce qui est exact, au lieu d'envoyer un secret étranger.
  #expect(CoffreDuHarness.jetonDuCoffre(autre) == nil)
  #expect(CoffreDuHarness.jetonDuCoffre("") == nil)
}

@Test("L'empreinte distingue deux jetons sans les révéler")
func empreinteNeReveleRien() {
  let un = String(repeating: "a", count: 43)
  let deux = String(repeating: "b", count: 43)

  let empreinteUn = Empreinte.de(un)
  #expect(empreinteUn == Empreinte.de(un), "la même valeur doit donner la même empreinte")
  #expect(empreinteUn != Empreinte.de(deux), "deux jetons différents ne doivent pas se confondre")

  // RÈGLE #0 : ce qui va dans le diagnostic est une empreinte, jamais le secret.
  // Elle ne doit donc rien laisser deviner du jeton lui-même.
  #expect(!empreinteUn.contains(un))
  #expect(empreinteUn.count == 16, "huit octets en hexadécimal")
}
