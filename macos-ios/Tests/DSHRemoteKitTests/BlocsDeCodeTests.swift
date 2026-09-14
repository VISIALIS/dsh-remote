import Foundation
import Testing

@testable import DSHRemoteKit

// LE DÉCOUPAGE DES BLOCS DE CODE, ÉPROUVÉ.
//
// C'est une règle, avec ses cas tordus : une clôture jamais fermée, des accents
// graves en pleine phrase, un langage annoncé ou non. Chaque cas ci-dessous
// correspond à quelque chose qu'un agent écrit réellement — ou à une façon de se
// tromper qui produirait un cadre de code autour de texte ordinaire.

@Test("Un texte sans bloc reste un seul segment de texte")
func texteSansBloc() {
  let segments = BlocsDeCode.decouper("Bonjour.\nDeuxième ligne.")
  #expect(segments == [.texte("Bonjour.\nDeuxième ligne.")])
}

@Test("Un bloc délimité devient du code, avec son langage")
func blocAvecLangage() {
  let segments = BlocsDeCode.decouper(
    """
    Voici la commande :
    ```bash
    tailscale serve --bg --http=80 http://127.0.0.1:3080
    ```
    Elle publie le port.
    """)

  #expect(segments.count == 3)
  #expect(segments[0] == .texte("Voici la commande :"))
  #expect(segments[1] == .code("tailscale serve --bg --http=80 http://127.0.0.1:3080", langue: "bash"))
  #expect(segments[2] == .texte("Elle publie le port."))
}

@Test("Un bloc sans langage annoncé est un bloc quand même")
func blocSansLangage() {
  let segments = BlocsDeCode.decouper(
    """
    ```
    swift build
    ```
    """)
  #expect(segments == [.code("swift build", langue: nil)])
}

@Test("Un bloc NON FERMÉ va jusqu'à la fin — un message tronqué garde son contenu")
func blocNonFerme() {
  // L'hôte peut couper un message ; les trois accents graves d'ouverture sont
  // alors dans le texte sans leur fermeture. Perdre le contenu serait pire que
  // l'afficher dans un cadre.
  let segments = BlocsDeCode.decouper(
    """
    Avant.
    ```swift
    let a = 1
    let b = 2
    """)

  #expect(segments.count == 2)
  #expect(segments[0] == .texte("Avant."))
  #expect(segments[1] == .code("let a = 1\nlet b = 2", langue: "swift"))
}

@Test("Les accents graves EN MILIEU de ligne ne sont pas des délimiteurs")
func accentsGravesEnLigne() {
  // C'est le piège : `code` en ligne est du Markdown courant, et le prendre pour
  // une clôture couperait la phrase en deux.
  let segments = BlocsDeCode.decouper("Le champ `jeton` doit être collé.")
  #expect(segments == [.texte("Le champ `jeton` doit être collé.")])
}

@Test("Une phrase qui COMMENCE par trois accents graves n'ouvre pas de bloc")
func fausseCloture() {
  // Trois accents graves suivis d'une phrase ne sont pas une clôture : une
  // clôture ne porte qu'un nom de langage, court, fait de lettres et de quelques
  // signes.
  let segments = BlocsDeCode.decouper("``` est la syntaxe d'un bloc de code en Markdown.")
  #expect(segments == [.texte("``` est la syntaxe d'un bloc de code en Markdown.")])
}

@Test("Deux blocs dans un même message, avec le texte entre eux")
func deuxBlocs() {
  let segments = BlocsDeCode.decouper(
    """
    Premier :
    ```
    a
    ```
    Second :
    ```sh
    b
    ```
    """)

  #expect(segments.count == 4)
  #expect(segments[0] == .texte("Premier :"))
  #expect(segments[1] == .code("a", langue: nil))
  #expect(segments[2] == .texte("Second :"))
  #expect(segments[3] == .code("b", langue: "sh"))
}

@Test("Un bloc VIDE n'est pas un bloc : pas de cadre pour rien")
func blocVide() {
  #expect(BlocsDeCode.decouper("```\n```") == [])
  // Et un texte fait uniquement de blancs ne produit rien non plus : la vue n'a
  // pas à dessiner une ligne vide.
  #expect(BlocsDeCode.decouper("   \n\n  ") == [])
  #expect(BlocsDeCode.decouper("") == [])
}

@Test("Un journal écrit sous Windows ne perd pas sa clôture")
func retourChariot() {
  let segments = BlocsDeCode.decouper("Avant\r\n```\r\nswift test\r\n```\r\nAprès")
  #expect(segments.count == 3)
  #expect(segments[1] == .code("swift test", langue: nil))
  #expect(segments[2] == .texte("Après"))
}

@Test("Le langage est rendu tel quel, et une clôture plus longue ferme aussi")
func langageEtClotureLongue() {
  // Certains agents ferment avec plus de trois accents graves quand le contenu
  // en contient : la fermeture doit être reconnue.
  let segments = BlocsDeCode.decouper(
    """
    ````markdown
    ```interne```
    ````
    """)
  #expect(segments.count == 1)
  #expect(segments[0] == .code("```interne```", langue: "markdown"))
}
