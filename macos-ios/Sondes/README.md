# Sondes — mesurer ce qu'un écran ne dit pas

Ce dossier ne contient **pas** de code de l'application. Il contient des sondes : de
petites applications isolées qui répondent à une question que la lecture du code ne
tranche pas, et dont la réponse doit être **mesurée** plutôt que supposée.

## `dialogue` — que fait ÉCHAP sur une confirmation destructive ?

**LA QUESTION.** « Réinitialiser l'application » efface des jetons, et macOS place la
confirmation dans un `confirmationDialog` SwiftUI. Une touche ÉCHAP peut-elle
déclencher l'action destructive ? Si oui, c'est un défaut de sécurité : un geste
d'annulation réflexe effacerait des secrets.

**LES RÉPONSES, MESURÉES** (macOS 26, SDK 26, variante « telle quelle » = structure
exacte de `VueReglages` : bouton destructif déclaré en premier, puis `.cancel`) :

| Geste | Journal | Verdict |
|---|---|---|
| Clic sur « Reinitialiser l'application » | `bouton-presse` | la confirmation s'ouvre |
| **ÉCHAP** | `ISSUE=annule` | **annule** — mesuré sur les deux variantes |
| **RETOUR** | *(rien)* | **aucun bouton par défaut** : la touche n'agit pas |
| Clic sur « Tout effacer » | `ISSUE=destructif` | le contrôle positif : la sonde sait voir l'action |

Le contrôle positif compte autant que les autres lignes : sans lui, « ÉCHAP annule »
pourrait vouloir dire « la sonde ne détecte rien ».

**CE QU'ELLE A APPRIS D'ELLE-MÊME.** Une fenêtre `NSWindow` construite AVANT
`NSApplication.run()` n'est jamais posée : `count of windows` valait `0` et rien ne
s'affichait. La sonde crée donc sa fenêtre dans `applicationDidFinishLaunching`, comme
une application réelle.

**COMMENT LA RELANCER.** La sonde journalise CHAQUE issue dans un fichier, parce qu'un
écran ne dit pas qui a agi, et l'horodatage permet de rapprocher un geste d'une ligne :

```bash
cd Sondes/dialogue
swift build
JOURNAL=/tmp/sonde.txt VARIANTE=A-telle-quelle .build/debug/EssaiDialogue &
```

Puis, dans l'ordre, avec `osascript` (ou à la main) :

1. cliquer « Reinitialiser l'application » → `bouton-presse` ;
2. presser ÉCHAP → `ISSUE=annule` ;
3. rouvrir, presser RETOUR → rien ;
4. rouvrir, cliquer « Tout effacer » → `ISSUE=destructif`.

`VARIANTE=B-durcie` ajoute `.keyboardShortcut(.cancelAction)` sur « Annuler » : elle
sert à vérifier que ce n'est PAS ce raccourci qui fait annuler ÉCHAP. Mesuré : les deux
variantes annulent, donc le rôle `.cancel` **suffit**, le raccourci explicite n'est pas
nécessaire.

**POUR PILOTER LA CONFIRMATION PAR `osascript`.** Les boutons d'un
`confirmationDialog` SwiftUI n'ont PAS de nom accessible (`missing value`) : on les
désigne par leur **index**, et la feuille se lit sur la fenêtre.

```applescript
tell application "System Events" to tell process "EssaiDialogue"
  click button 2 of sheet 1 of window 1   -- 2 = « Tout effacer »
end tell
```

Le piège mesuré : un clic synthétique à quelques points SOUS le bouton ne fait rien du
tout — ni action, ni message. Les positions se lisent donc (`position of every button
of sheet 1 of window 1`) au lieu de s'estimer sur une capture.
