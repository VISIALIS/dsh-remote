# Sondes — mesurer ce qu'un écran ne dit pas

Ce dossier ne contient **pas** de code de l'application. Il contient des sondes :
de petites applications isolées qui répondent à une question que la lecture du code
ne tranche pas, et dont la réponse doit être **mesurée** plutôt que supposée.

## `dialogue` — que fait ÉCHAP sur une confirmation destructive ?

**LA QUESTION.** « Réinitialiser l'application » efface des jetons, et macOS place la
confirmation dans un `confirmationDialog` SwiftUI. La question posée est simple : une
touche ÉCHAP peut-elle déclencher l'action destructive ? Si oui, c'est un défaut de
sécurité — un geste d'annulation réflexe effacerait des secrets.

**LA RÉPONSE, MESURÉE.** ÉCHAP **annule**. Le journal de la sonde, sur macOS 26
(SDK 26), variante « telle quelle » — c'est-à-dire la structure exacte de
`VueReglages`, bouton destructif déclaré en premier, puis `.cancel` :

```text
1789396275 lance
1789396309 bouton-presse
1789396316 ISSUE=annule        ← ÉCHAP
```

**COMMENT LA RELANCER.** La sonde journalise CHAQUE issue dans un fichier, parce qu'un
écran ne dit pas qui a agi :

```bash
cd Sondes/dialogue
swift build
JOURNAL=/tmp/sonde.txt VARIANTE=A-telle-quelle .build/debug/EssaiDialogue &
# 1. cliquer « Reinitialiser l'application »   → « bouton-presse »
# 2. presser ÉCHAP                             → « ISSUE=annule »
# 3. cliquer « Tout effacer »                  → « ISSUE=destructif »
```

La variante `B-durcie` ajoute `.keyboardShortcut(.cancelAction)` sur « Annuler » : elle
sert à vérifier que ce n'est PAS ce qui fait annuler ÉCHAP. Mesuré également :
`ISSUE=annule` sans le raccourci explicite, donc le rôle `.cancel` suffit.

**CE QUE LA SONDE A APPRIS D'ELLE-MÊME.** Une fenêtre `NSWindow` construite AVANT
`NSApplication.run()` n'est jamais posée : `count of windows` valait `0` et rien ne
s'affichait. La sonde crée donc sa fenêtre dans `applicationDidFinishLaunching`, comme
une application réelle.
