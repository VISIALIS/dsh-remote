# Audit UX/UI et conformité Apple — `DSH Remote` (macOS + iPhone)

État audité : commit `d78695b`, arbre de travail propre. Audit demandé le 13/09.
**Ce document est un rapport, pas un correctif : l'audit n'a modifié aucun fichier de
code.** Les correctifs du P0, faits ensuite, sont consignés au § 10.

---

## 1. Ce qui a été fait, et comment le croire

Six réviseurs **indépendants** ont reçu le même brief de 239 lignes — contexte produit,
périmètre fichier par fichier, faits techniques, décisions déjà prises à ne pas re-litiger,
interdits de lecture seule, format de sortie imposé — et aucun n'a vu les avis des autres.

| Réviseur | Version / modèle | Rendu |
|---|---|---|
| Claude Code | 2.1.268, modèle par défaut | 82 lignes |
| Codex CLI | 0.154.0, `gpt-6-astra`, effort `xhigh`, bac à sable `read-only` | 112 lignes |
| muse | Muse Code 1.2.1 | 60 lignes |
| agy | Gemini, modèle par défaut | 53 lignes |
| grok | Grok Build, `grok-4.6`, mode `plan` | 97 lignes |
| DSH (DeepSeek Harness) | `deepseek-flash`, contexte neuf | 89 lignes |

**Garanties de méthode, chacune vérifiée :**

- Le panel a travaillé sur une **copie** du dépôt (`/tmp/dsh-audit-ux/snapshot/`), jamais sur
  l'original. Empreinte SHA-256 des **108 fichiers** du dépôt prise avant et après :
  **identique** — aucune écriture du panel, ni dans le dépôt, ni dans le bac à sable.
- Aucun build, aucun simulateur, aucun `git` : la revue est statique, et elle le dit.
- Les citations `fichier:ligne` des avis ont été **contrôlées mécaniquement** (script
  `verifier-citations.py`) : sur les **430 références** des six avis, **0 fichier absent,
  0 ligne hors fichier, 0 extrait introuvable**. Aucun réviseur n'a donc inventé une preuve.
- Les constats qu'**un seul** réviseur avait vus — les plus suspects, et les plus graves —
  ont été soumis à un vérificateur indépendant, puis relus par moi. Trois d'entre eux
  étaient exacts et sous-estimés, un était à scinder, un à reformuler : c'est signalé
  ligne à ligne au § 4.
- **Aucun constat retenu n'est resté invérifié** : chaque ligne du § 4 a été relue dans le
  code ou mesurée. Ce qui ne peut pas être tranché sans exécuter l'application — rendu,
  contrastes, gestes réels — est regroupé au § 8 sous forme de tests à faire.
- **Divulgation assumée** : le code Swift et deux captures d'écran ont été transmis aux
  fournisseurs des cinq CLI externes. Les captures ont été inspectées avant envoi (aucun
  jeton visible — il vit dans une section repliée) ; aucun avis ne contient le suffixe réel
  du tailnet ni d'adresse privée. Le dépôt, lui, ne contient aucun de ces éléments.

Convergence notée `n/6` : nombre de réviseurs ayant soulevé le point **indépendamment**.
Les initiales sont celles du tableau ci-dessus (C, X, M, A, G, D).

---

## 2. Verdict

L'application est **bien conçue et mal finie** : son modèle mental — diagnostic en quatre
constats, un seul vocabulaire d'état, aucun bouton sans effet — est meilleur que celui de
la plupart des clients internes, et deux réviseurs sur six ont explicitement validé les
décisions contestables (titre en ligne, recherche ancrée en bas, carrousel, un seul geste
pour connecter et ouvrir).

Mais **elle n'est pas conforme aux directives Apple**, et pas seulement par manque de
finition : il manque la **couche d'adaptation** (Dynamic Type, VoiceOver, Reduce Motion,
gestes natifs, menus et raccourcis Mac) que les six réviseurs ont relevée sans se concerter.
Et elle souffre d'un défaut plus grave, que **deux réviseurs seulement** ont vu et que j'ai
confirmé dans le code : **sur un iPhone neuf, il est impossible de saisir le jeton
d'authentification** — le seul champ existe sur la page d'une machine, laquelle ne s'ouvre
qu'après une découverte, laquelle exige une connexion authentifiée.

---

## 3. Les trois constats qui commandent le reste

### 3.1 BLOQUANT — l'iPhone neuf ne peut pas s'authentifier (2/6 : X, G — vérifié par moi)

Trois chemins de saisie du jeton existent dans tout le code : la page d'une machine
(`VueServeur.swift:283-312`), l'amorçage macOS depuis le coffre (`Vues.swift:166`), et le
fichier de configuration d'amorçage (`ModeleApp.swift:1615`). **Aucun n'est atteignable
depuis un iPhone vierge** :

1. la liste est vide, donc `serveurs` est vide ;
2. `serveurVise` se calcule par `serveurA(adresse:dans:)` (`ModeleApp.swift:523-533`) : une
   adresse saisie à la main **n'appartient à aucune machine connue**, donc la page de
   serveur ne s'ouvre pas — et c'est exactement la garde de `Vues.swift:189-192` ;
3. la feuille « Saisir une adresse » (`FeuilleAdresse.swift:22-58`) porte l'adresse, « Se
   connecter », « Tester l'adresse » — **et aucun champ de jeton** ;
4. quand la connexion échoue en `401`, le message affiché dit :
   « … Recopiez le jeton affiché par le harness, puis collez-le **dans Réglages** »
   (`Modeles.swift:385-386`) — or la feuille Réglages est **vide** depuis la refonte
   (`VueReglages.swift:38-56`).

Autrement dit : le remède prescrit pointe vers un écran vide, et le champ réel est derrière
une porte fermée. Le README documente le chemin (saisir le jeton une fois), l'application ne
l'offre plus. **Correctif** : porter le couple adresse + jeton dans la feuille Adresse (ou
dans la page « Ajouter un serveur »), et corriger le message du `401`. Effort : faible.

### 3.2 MAJEUR — l'adresse suggérée sur iPhone est un piège (3/6 : G, D, C-nuancé)

Le champ d'adresse affiche et conseille un nom MagicDNS en clair :

- placeholder iOS : `http://mon-mac.mon-tailnet.ts.net` (`ModeleApp.swift:1375-1379`) ;
- pied de page : « Le nom MagicDNS de la machine, publié par `tailscale serve` — par exemple
  `mon-mac.mon-tailnet.ts.net` » (`FeuilleAdresse.swift:80-82`).

App Transport Security bloque le clair vers un nom qualifié ; la règle du dépôt — écrite
dans le README — est d'utiliser **l'IP littérale** (`http://100.x.y.z:3080`). L'application
construite s'en sort par une exception ATS injectée **dans le `.app` construit** par une
phase de build, depuis `Config/DomaineTailnet`, fichier local non versionné
(`project.pbxproj:149`, `Scripts/injecter-exception-ats.sh:46,58`). **Mesuré** : l'exception
présente dans les `.app` construits correspond bien au tailnet réel, et à ce fichier — donc
la recette fonctionne *sur cette machine*. Mais un clone du dépôt produit une application
qui ne peut joindre aucun nom MagicDNS en HTTP, **sans erreur de build**, et l'interface
continue de conseiller ce chemin. **Correctif** : conseiller l'IP littérale sur iOS, ou
publier en HTTPS (`tailscale serve --https 443`) et supprimer la phase d'injection.

### 3.3 MAJEUR — il manque la couche d'adaptation (6/6, sans exception)

| Manque | Preuve | Ce que ça coûte |
|---|---|---|
| **Dynamic Type** : cinq tailles en points absolus (9, 19, 24, 27, 30) et des cadres figés (62, 68 pt) avec `lineLimit(1)` | `Vues.swift:666,676,706,795` ; `VueServeur.swift:73` ; `Vues.swift:663,692,699-701,708,789,801,806` | À taille d'accessibilité, la légende de vignette est illisible et le nom tronqué : or c'est **le seul endroit qui dit « pas de DSH »** |
| **VoiceOver** : les états de session et d'étape n'ont ni libellé ni valeur ; l'information est portée par la forme et la couleur | `Vues.swift:942-1000`, `1042-1073` ; `ParcoursDesEtapes.swift:73-77,121-135` | Un utilisateur non-voyant lit une liste de sessions sans savoir laquelle l'attend — l'information la plus actionnable de l'application |
| **Reduce Motion** : rotation en boucle infinie, sans consulter le réglage ; `EtatSession.anime` existe et n'est **jamais lu** | `Vues.swift:968-972` ; `EtatSession.swift:69` | Animation perpétuelle sur chaque session active, y compris quand le système demande l'inverse |
| **Cibles tactiles** : boutons d'icône à `.font(.caption)` ou `.title2` en style `.plain`, sans surface élargie | `LigneCommande.swift:39-47` ; `VueEcriture.swift:53,65` ; `VueServeur.swift:296-311` ; `Vues.swift:911` | Copier une commande, coller un jeton, interrompre un tour : les gestes les plus fréquents et les plus coûteux à rater |
| **États trop proches** : « attend une réponse » est un point orange de 8 pt, « terminée » un point vert de 7 pt | `Vues.swift:974-990` | Un point de différence n'est pas un code visuel ; la confusion entre « ça tourne » et « ça t'attend » est précisément celle qui compte |

---

## 4. Conformité Apple — tableau consolidé

Statut : ✔ vérifié par moi dans le code · ◐ vérifié partiellement · ○ non vérifié (à tester).
Gravité : **BLOQUANT** · **MAJEUR** · **MINEUR** · **GOÛT**.

### 4.1 Accessibilité

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| A1 | Dynamic Type inopérant : tailles absolues, cadres figés, `lineLimit(1)` | MAJEUR | 6/6 | ✔ | `Vues.swift:666,676,706,795` ; `VueServeur.swift:73` | Styles sémantiques, `@ScaledMetric`, `ViewThatFits` ; éprouver en AX5 | M |
| A2 | VoiceOver muet sur les états (session, étape, machine choisie) | MAJEUR | 6/6 | ✔ | `Vues.swift:942-1000,1042-1073` ; `ParcoursDesEtapes.swift:73-77` | `.accessibilityElement(children:.combine)` + libellé d'état ; masquer le décor | S |
| A3 | `accessibilityReduceMotion` ignoré ; `EtatSession.anime` jamais lu | MAJEUR | 6/6 | ✔ | `Vues.swift:968-972` ; `EtatSession.swift:69` | Indicateur statique si le réglage est actif | S |
| A4 | Cibles tactiles sous la cible de référence de 44 pt | MAJEUR | 4/6 | ✔ | `LigneCommande.swift:39-47` ; `VueEcriture.swift:53,65` | `.frame(minWidth:44,minHeight:44)` + `.contentShape` | S |
| A5 | Information portée par la couleur et une forme quasi identique | MAJEUR | 6/6 | ✔ | `Vues.swift:974-990,725-729,695` | Symbole distinct par état + mot équivalent | S |
| A6 | Légende de vignette à 9 pt, sous le minimum recommandé (11 pt iOS / 10 pt macOS) | MAJEUR | 5/6 | ✔ | `Vues.swift:705-709` | `.caption2`, deux lignes autorisées | S |

### 4.2 Structure, navigation et gestes (iOS)

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| B1 | **iPhone neuf : jeton insaisissable, remède pointant vers des Réglages vides** | **BLOQUANT** | 2/6 | ✔ | voir § 3.1 | Jeton dans la feuille Adresse ; corriger le message `401` | S |
| B2 | Adresse suggérée = MagicDNS en HTTP, hors de la règle du dépôt | MAJEUR | 3/6 | ✔ | voir § 3.2 | Conseiller l'IP littérale, ou HTTPS | S |
| B3 | `NavigationLink` + `simultaneousGesture` : VoiceOver et clavier n'activent que le lien, la connexion est un geste parallèle | MAJEUR | 4/6 | ✔ | `Vues.swift:551-565,609-614` | Une sélection unifiée ; connexion dans l'action du lien | M |
| B4 | Aucun geste natif : ni `.refreshable`, ni `.swipeActions`, ni `.contextMenu` dans tout le dépôt | MAJEUR | 5/6 | ✔ | `Vues.swift:274-409` (`List` nue) | Les trois, sur les sessions et les machines | M |
| B5 | Pas d'état vide pour l'arbre des sessions, ni d'état « aucun résultat » de recherche | MAJEUR | 4/6 | ✔ | `Vues.swift:324-393` ; `ContentUnavailableView` n'existe que dans le détail | `ContentUnavailableView` + `.search` dans la liste | S |
| B6 | L'actionnable est enterré : aucun filtre par état, aucun tri par urgence ; `nbVivantes` existe et n'est pas utilisé | MAJEUR | 5/6 | ✔ | `Vues.swift:386-388` ; `Regroupement.swift:26` | Section « demande votre attention » + compteur par état | M |
| B7 | Échec de connexion **silencieux** dès qu'une session est ouverte | MINEUR | 2/6 | ✔ | `Vues.swift:189-192` (la garde exclut les deux cas les plus fréquents) | Bandeau non bloquant, ou page d'erreur prioritaire | S |
| B8 | Interrompre un tour : glyphe rouge de 22 pt adjacent au bouton d'envoi, **sans confirmation** | MAJEUR | 4/6 | ✔ | `VueEcriture.swift:61-70` | Cible 44 pt, séparation, confirmation | S |
| B9 | Le mode d'envoi est caché derrière une icône, alors que le même fichier écrit la règle inverse ; Envoyer et Interrompre n'ont pas de libellé d'accessibilité | MINEUR | 2/6 | ✔ | `VueEcriture.swift:17-19` contre `:85-105`,`:50-70` | Libellé du mode visible ; noms d'action explicites | S |
| B10 | La recherche ne couvre pas le titre de l'espace et ignore les accents (le `cwd` et le `preset`, eux, sont bien fouillés) | MINEUR | 1/6 | ✔ | `ModeleApp.swift:1880-1890` ; `Vues.swift:901` | Inclure le nom d'espace, replier les diacritiques | S |
| B11 | Barre de recherche sans gestion de focus ni touche Rechercher : aucun `@FocusState`, `.submitLabel`, `.onSubmit` ni `.scrollDismissesKeyboard` | MINEUR | 1/6 | ✔ | `Vues.swift:894-933` (le seul `FocusState` du paquet est dans `VueEcriture.swift:25`) | Focus, touche Rechercher, fermeture du clavier au défilement | S |

### 4.3 macOS — la plateforme la moins servie

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| C1 | Aucune scène `Settings`, donc pas de ⌘, ni d'entrée « Réglages… » ; l'engrenage ouvre une feuille **vide** (une phrase), et le `401` y renvoie | MAJEUR | 6/6 | ✔ | `main.swift:70-76` ; `Vues.swift:451-460` ; `VueReglages.swift:38-56` | Scène `Settings` avec du contenu réel, ou retirer le bouton | S–M |
| C2 | Aucune commande ni raccourci : `keyboardShortcut`, `.commands`, `CommandGroup` = **0 occurrence** | MAJEUR | 5/6 | ✔ | `main.swift:70-76`, absence confirmée dans `Sources/` | ⌘R rafraîchir, ⌘F rechercher, ⌘↩ envoyer, ⌘⌫ supprimer | M |
| C3 | `WindowGroup` + `@State ModeleApp()` par fenêtre : ⌘N ouvre un client parallèle, sans restauration d'état | MINEUR | 3/6 | ✔ | `main.swift:71` ; `Vues.swift:11` | `Window` unique, ou état partagé | M |
| C4 | Fenêtre plancher à 900 pt de large, colonne latérale à 320 pt : pas de mode étroit | MINEUR | 2/6 | ✔ | `main.swift:73` ; `Vues.swift:430` | Masquage automatique du panneau en fenêtre étroite | M |
| C5 | Le nom de la machine est affiché **deux fois** (barre de titre et corps de page) | MINEUR | 1/6 | ✔ | `VueServeur.swift:52` et `:77` | Garder la barre ; l'identité devient pastille + adresse | S |

### 4.4 Liquid Glass et chrome (SDK 26)

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| D1 | Barre de recherche : **deux** fonds empilés (`.regularMaterial` **et** `.background(.bar)`) plus un contour ; le contenu ne passe pas dessous. C'est le cas que la documentation Apple du SDK 26 demande explicitement d'éviter | MAJEUR | 5/6 | ✔ | `Vues.swift:920-932` | Un seul fond, ou `safeAreaBar` / `.searchable` ancré bas ; vérifier l'effet de bord de défilement | M |
| D2 | Composeur bâti de la même façon (bandeau `.bar`, champ à fond `.quaternary`, boutons `.plain` dessinés à la main) | MINEUR | 3/6 | ✔ | `VueEcriture.swift:42,50-59,75` | Styles de contrôle du SDK 26, avec repli `#available` | M |
| D3 | Cartes maison (`RoundedRectangle` + `.background.secondary`) au lieu d'encarts système | GOÛT | 3/6 | ✔ | `VueServeur.swift:206,234,375` | Aucun besoin de verre ici (**le verre est interdit dans la couche contenu**) ; migrer vers `Form` seulement si l'on veut les métriques système | L |
| D4 | Écran de lancement vide (`UILaunchScreen` sans contenu) : premier cadre blanc | MINEUR | 3/6 | ✔ | `App/Info.plist:36` | Fond cohérent + barre de titre | S |
| D5 | Feuilles sans `presentationDetents` : plein écran pour un champ | MINEUR | 1/6 | ✔ | `Vues.swift:158-163` ; `FeuilleAdresse.swift:16-94` | `.medium` + `.large` | S |

### 4.5 Fiabilité des actions — trouvailles d'un seul réviseur, vérifiées

Ces quatre défauts ne sont pas esthétiques : ils font agir l'application **sur le mauvais
objet**. Codex les a trouvés seul ; je les ai relus ligne à ligne, ils sont exacts.

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| E1 | **Le brouillon est commun à toutes les sessions** : changer de session conserve le texte, qui peut partir vers une autre. `oublierEtatEcriture()` n'efface que les messages | MAJEUR | 1/6 | ✔ | `ModeleApp.swift:1759` (un seul champ), `:1835-1838` ; `VueEcriture.swift:76-80` | Brouillons par couple hôte/session | M |
| E2 | **L'acquittement efface aussi la frappe concurrente** : `brouillon = ""` s'applique après l'attente réseau, alors que le champ reste modifiable pendant l'envoi (le modèle le dit lui-même : « la frappe continue ») | MAJEUR | 1/6 | ✔ | `ModeleApp.swift:1794-1811` | N'effacer que la version effectivement acquittée | S |
| E3 | **Le champ du jeton agit sur la cible, pas sur la machine affichée** : la page dit « jeton de cet hôte », l'écriture et l'effacement visent `cible.adresse` | MAJEUR | 1/6 | ✔ | `VueServeur.swift:279-287,304-311` ; `ModeleApp.swift:1503,1507-1512` | Lier lecture, collage, remplacement et effacement à l'hôte de la page | M |
| E4 | Journal : une lecture échouée laisse l'**ancien** journal sous le titre de la **nouvelle** session. Rien n'est vidé avant la requête, `appliquerJournal` n'est appelé qu'en cas de succès, l'en-tête lit encore `sessionOuverte` (l'ancienne), le voile de chargement est conditionné à `journal.isEmpty`, et la vue ne lit jamais `connexion` : ni contenu juste, ni chargement, ni erreur | MAJEUR | 1/6 | ✔ | `ModeleApp.swift:1677-1686,1913-1928` ; `VueJournal.swift:16,38,43,66` | Associer les événements à leur session ; état d'échec local avec réessai | M |
| E5 | « Développer » dépend d'un seuil de **120 caractères**, indépendant des **4 lignes** affichées : un message de six lignes courtes (~90 caractères) est tronqué **sans bouton**, et la ligne n'offre ni geste ni lien — le texte complet devient illisible | MINEUR | 1/6 | ✔ | `Evenements.swift:92-94` ; `VueJournal.swift:122-130` | Décider sur la troncature réelle, ou toujours offrir le texte complet | S |
| E6 | Page « Ajouter un serveur » : les étapes 2 à 4 sont codées en dur `.aFaire`, la frontière ne peut donc pas avancer, les étapes 3 et 4 sont grisées et leur méthode n'est jamais rendue — « publier le port » et « installer le plugin » y sont **inatteignables**. (Ces deux démarches restent accessibles depuis la page d'une machine connue : le cul-de-sac est propre à la page d'ajout) | MAJEUR | 1/6 | ✔ | `EtapesServeur.swift:225,231,236` ; `ParcoursDesEtapes.swift:69,93,105` ; `VueAjoutServeur.swift:61,110-114` | Une validation explicite de l'étape faite, ou un constat vérifiable par la sonde | M |
| E7 | Un collage refusé n'a aucun retour : `collerLeJeton()` rend un booléen que l'unique appelant jette. Un presse-papiers vide ou trop court ne produit rien — l'inverse de la règle que le dépôt s'énonce et applique ailleurs (l'action Tailscale, elle, signale son échec) | MINEUR | 1/6 | ✔ | `ModeleApp.swift:1449-1464` ; `VueServeur.swift:296-302` ; contre-exemple `VueAjoutServeur.swift:82-85` | `PasteButton` + message contextualisé | S |

### 4.6 Manques fonctionnels et finitions

| # | Constat | Gravité | Conv. | St. | Preuve | Correctif | Effort |
|---|---|---|---|---|---|---|---|
| F1 | **Aucune notification ni badge** : « l'agent attend » et « c'est fini » ne se voient qu'à l'écran, alors que la détection existe déjà en mémoire | MAJEUR | 6/6 | ✔ | aucun `UserNotifications` ; `RappelsDeFin.swift:22-28` ; `ModeleApp.swift:641` | Notification locale tant que l'app tourne ; documenter la limite (voir § 7) | M |
| F2 | **Le journal ne suit pas sa fin** : aucun `ScrollViewReader`, aucun `scrollTo`, aucun « Revenir en bas » | MAJEUR | 6/6 | ✔ | `VueJournal.swift:15-42` | Suivre la fin si l'on y est déjà + compteur de nouveaux événements | S |
| F3 | `oublierServeur()` existe dans le modèle et n'a **aucune** porte d'entrée dans les vues | MINEUR | 2/6 | ✔ | `ModeleApp.swift:1470` (0 appel) | Menu contextuel / glissement sur une vignette | S |
| F4 | Carrousel : vignette coupée au bord (visible sur la capture macOS) et aucun indicateur de défilement | MINEUR | 2/6 | ◐ | capture `macos-page-serveur.png` ; `Vues.swift:625,293-294` | Marges internes, indice de défilement | S |
| F5 | Les vignettes n'affichent que le **premier mot** du nom : deux machines peuvent porter le même libellé (« Portable Un » et « Portable Deux » donnent tous deux « Portable ») alors que l'appui change immédiatement la connexion. VoiceOver, lui, reçoit le nom complet | MINEUR | 1/6 | ✔ | `DecouverteServeurs.swift:61-63` ; `Vues.swift:697,561-565` ; fixtures `Tests/DSHRemoteKitTests/DecouverteTests.swift:16,23` | Nom court discriminant ou alias | M |
| F6 | Aucune restauration d'état : session consultée, espaces dépliés, mode d'envoi repartent à zéro | MINEUR | 2/6 | ✔ | `Vues.swift:12,238` ; `VueEcriture.swift:24` | Persister la sélection et les dépliages | S |
| F7 | Presse-papiers lu directement (`UIPasteboard.general.string`) : bannière système à chaque collage | MINEUR | 4/6 | ✔ | `ModeleApp.swift:1453` ; `VueServeur.swift:296` | `PasteButton` | S |
| F8 | `PrivacyInfo.xcprivacy` absent (API à raison requise : `UserDefaults`, horodatages) | MINEUR | 2/6 | ✔ | aucun `.xcprivacy` ; `Persistance.swift:41-62` | Manifeste + raison `CA92.1` — **sans objet** tant que rien n'est soumis | S |
| F9 | Chaînes en dur, `AgeLisible` maison, pluriels assemblés à la main | GOÛT | 4/6 | ✔ | `App/Info.plist:5` ; `Regroupement.swift:223-233` ; `Vues.swift:264,407` | Assumé par la RÈGLE #1 ; à revoir seulement pour un second utilisateur | — |
| F10 | `TARGETED_DEVICE_FAMILY = 1` : pas d'iPad, et en paysage iPhone la largeur devient « regular » — un cas que personne n'a éprouvé | MINEUR | 4/6 | ✔ | `project.pbxproj:251,277` ; `Info.plist:39-46` | Assumer l'iPhone, ou traiter explicitement le paysage | M |
| F11 | L'app iOS ne se construit qu'avec des fichiers locaux non versionnés (équipe de signature, domaine ATS) : un clone ne produit pas la même application, sans erreur de build | MINEUR | 1/6 | ✔ | `Config/Base.xcconfig` ; `Config/DomaineTailnet` ; `Scripts/injecter-exception-ats.sh:46,58` | HTTPS sans exception, ou échec de build explicite si le fichier manque | S |
| F12 | Rendu Markdown et blocs de code dans le journal : les réponses de l'agent s'affichent en texte brut | GOÛT | 1/6 | ✔ | `VueJournal.swift:120-123` | Rendu Markdown + copie de bloc — confort, pas conformité | L |

---

## 5. Plan d'actions priorisé

### P0 — avant tout usage sur un iPhone neuf (une demi-journée)

1. **Rendre le premier serveur configurable de bout en bout** : le jeton saisissable (B1),
   **et** les méthodes des étapes 3 et 4 atteignables depuis la page « Ajouter un serveur »
   (E6) — les deux faces du même cul-de-sac de démarrage — puis **corriger le message du
   `401`** qui renvoie vers des Réglages vides.
2. **Ne plus conseiller un nom MagicDNS en HTTP sur iOS** (B2) : placeholder et pied de page
   vers l'IP littérale, ou passage à HTTPS.
3. **Accessibilité de base** (A2, A3, A4) : libellés d'état pour VoiceOver, respect de
   Réduire les animations, cibles de 44 pt sur les boutons d'icône. Une journée au total,
   et c'est ce qui change la classe de l'application.

### P1 — confiance : que l'application agisse sur le bon objet (deux à trois jours)

4. **Brouillon par session** (E1) et **acquittement qui ne détruit pas la frappe
   concurrente** (E2).
5. **Jeton lié à la machine affichée** (E3).
6. **Journal honnête** (F2, E4, E5) : suivre la fin, dire l'échec de lecture dans la session
   concernée, offrir le texte complet.
7. **Confirmer l'interruption d'un tour** (B8) et séparer les deux glyphes.
8. **Faire remonter ce qui attend** (B6, B5) : section « demande votre attention », compteur
   par état dans les en-têtes repliés, états vides explicites.

### P2 — gestes et surface native

9. **iOS** : `.refreshable`, `.swipeActions`, `.contextMenu`, retour haptique discret (B4).
10. **macOS** : scène `Settings` avec ⌘, **ou** retrait de l'engrenage vide (C1) ;
    commandes ⌘R / ⌘F / ⌘↩ (C2) ; menus contextuels (B4).
11. **Une seule navigation** pour connecter et ouvrir une machine (B3) — le choix produit
    reste, c'est son câblage qui doit couvrir VoiceOver, le clavier et le paysage.

### P3 — finitions

12. Un seul fond pour la barre de recherche et le composeur, `safeAreaBar` à l'étude (D1, D2).
13. Dynamic Type complet : `@ScaledMetric` sur les vignettes, styles sémantiques partout (A1, A6).
14. Titre dupliqué (C5), écran de lancement (D4), `presentationDetents` (D5), carrousel (F4),
    noms de machines (F5), restauration d'état (F6), `PasteButton` (F7).
15. `PrivacyInfo.xcprivacy` et manifeste de confidentialité (F8) — si et seulement si
    l'application est un jour soumise.

### P4 — décisions produit, à trancher par le propriétaire

- **Notifications** (F1) : la plus forte valeur d'usage, et le remède le plus incertain (§ 7).
- **iPad** (F10), **localisation** (F9), **rendu Markdown** (F12).

---

## 6. Divergences du panel, et mon arbitrage

C'est ici que six avis indépendants valent mieux qu'un : quatre points ont produit des
conclusions **contradictoires**, et l'arbitrage change ce qu'il faut faire.

| Point | Positions | Arbitrage |
|---|---|---|
| `NSLocalNetworkUsageDescription` | agy : **BLOQUANT** (5.1.1) · grok : MAJEUR · claude et codex : « pas automatiquement requis » · DSH : rien à signaler | **Non requis pour Tailscale** : le trafic passe par l'interface VPN, que la note technique d'Apple exclut du réseau local. À reconsidérer *seulement* si des adresses LAN deviennent un chemin pris en charge. La gravité « bloquante » d'agy est écartée. |
| Cartes de contenu et Liquid Glass | muse : passer les cartes au verre (`.glassEffect`) · grok et codex : les cartes en `.background.secondary` sont **correctes** | **grok et codex ont raison** : la documentation du SDK 26 interdit explicitement le verre dans la couche de contenu. Seule la barre fonctionnelle (recherche, composeur) est concernée. |
| iPad | muse et agy : MAJEUR, « instable sur tablette » · codex : périmètre iPhone assumé, pas une non-conformité | **Périmètre légitime** (`TARGETED_DEVICE_FAMILY = 1`). Le vrai point, soulevé par grok, est le **paysage iPhone** en largeur « regular », non éprouvé. Gravité ramenée à MINEUR. |
| `WindowGroup` et fenêtres | agy et grok : défaut · codex : `WindowGroup` fournit l'infrastructure système, pas un défaut | **MINEUR** : le défaut n'est pas le multi-fenêtres mais le **modèle indépendant par fenêtre**. |
| Notifications | claude et grok : « la détection existe, c'est du câblage » · codex et agy : « pas fiable sur iPhone suspendu » | **Codex et agy sont plus justes** : sans push, une application suspendue ne détecte rien. Une notification locale n'est honnête que tant que l'application tourne. |
| Cible tactile de 44 pt | agy et muse : écart ferme · codex : « 44 pt est une cible de référence, pas un seuil de rejet » | **Codex a raison sur la formulation** : la HIG donne 44 × 44 pt par défaut et 28 × 28 pt en minimum absolu. Le constat reste (les boutons d'icône sont plus petits), la gravité reste MAJEUR pour l'usage au pouce. |
| Recherche ancrée en bas | claude : « écart assumé et justifié » · grok : garder l'ancre, corriger le matériau et le rôle · DSH : préférer `.searchable` bas | **Garder l'ancre** (décision du propriétaire, validée par deux réviseurs) et **corriger le matériau** : le problème n'est pas la position, c'est le fond empilé. |
| `NavigationLink` + `simultaneousGesture` | muse : « fragile » · claude : « risque, non observé » · grok et codex : « VoiceOver n'active que le lien » | **Retenu** : le défaut est réel pour l'activation non gestuelle (VoiceOver, clavier, interrupteur). C'est le seul point où un choix produit se heurte à l'accessibilité. |

---

## 7. Ce que le panel confirme comme déjà bon — à ne pas casser

Six avis séparés ont validé, sans se concerter, les mêmes choix. Ce sont les actifs du
produit :

- **Le diagnostic en quatre constats**, avec sa conclusion en tête et **une seule** méthode
  dépliée : « un vrai modèle mental » (grok), « exemplaire » (muse), « meilleur que la
  moyenne » (DSH). Partagé entre les deux pages sans duplication.
- **« Un bouton sans effet est un mensonge d'interface »**, tenue sans exception : le
  composeur n'apparaît que si l'hôte sait écrire, « Arrêter » que si l'annulation est
  annoncée, « Chercher » que si la recherche peut rendre quelque chose, et l'action
  principale change avec l'état.
- **Le tri-état `Bool?`** — « je ne sais pas » n'est jamais rendu comme « non » : sonde,
  tailnet, étapes. Claude en fait la discipline la plus rare du dépôt.
- **Un vocabulaire unique** (`EtatMachine`), partagé entre la vignette et la page, éprouvé
  par des tests.
- **Le jeton** : `SecureField`, trousseau par hôte sur iOS, mémoire sur macOS, jamais dans
  les préférences, jamais journalisé, compteur de caractères au lieu du contenu.
- **Le brouillon n'est effacé qu'après acquittement**, avec identifiant d'envoi idempotent —
  l'intention est bonne ; ce sont les changements de contexte qui la trahissent (E1, E2).
- **Les commandes copiables** avec acquittement visuel et libellé d'accessibilité distinct.
- **Les décisions contestables tiennent** : titre en ligne (60 pt rendus aux sessions),
  recherche en bas, carrousel d'icônes, un seul geste pour connecter et ouvrir.
- **La liste vide explique et offre une sortie**, l'icône est complète (claire, sombre,
  teintée), `LSApplicationQueriesSchemes` évite d'envoyer à l'App Store une application déjà
  installée.

---

## 8. Ce qui ne peut pas être tranché sans un appareil

Aucun réviseur n'a exécuté l'application (interdit du brief) — et aucun n'a mesuré un
contraste, une zone tactile réelle ou un rendu. Les six avis convergent sur cette liste de
vérifications à faire **au simulateur puis sur l'iPhone**, une fois P0 fait :

1. **Liquid Glass sous SDK 26** : apparence réelle des barres d'outils système, lisibilité du
   contenu sous la barre de recherche maison, coins des feuilles.
2. **Dynamic Type en taille d'accessibilité maximale** : ce que devient le carrousel, et si
   la légende de 9 pt disparaît ou déborde.
3. **VoiceOver** : ordre de lecture de la liste, état des pastilles, et surtout si l'appui sur
   une vignette de machine **connecte** réellement (B3) au doigt, au clavier et sous VoiceOver.
4. **Contrastes** en mode sombre et avec « augmenter le contraste » : orange sur fond
   système, styles tertiaires, opacités cumulées.
5. **L'invite « réseau local »** apparaît-elle, oui ou non, sur un iPhone réel connecté au
   tailnet ? (trois avis divergents ; une minute de test tranche).
6. **Paysage iPhone** en largeur « regular » : la page d'une machine tient-elle ?
7. **Fraîcheur de la page serveur** : la destination reçoit une valeur `ServeurMac` figée,
   alors que la liste est remplacée à chaque synchronisation (soulevé par codex seul).
8. **Bannière de collage** à chaque appui sur « Coller le jeton » (F7).

---

## 9. Annexe — pièces et méthode

| Pièce | Où |
|---|---|
| Les six avis bruts, tels que rendus | `/tmp/dsh-audit-ux/avis-{claude,codex,muse,agy,grok,deepseek}.md` |
| Le brief commun du panel | `/tmp/dsh-audit-ux/prompt.md` |
| Le référentiel HIG (85 exigences sourcées sur les pages Apple) | produit pour cet audit ; voir ci-dessous |
| Le vérificateur de citations | `/tmp/dsh-audit-ux/verifier-citations.py` |
| Résultat de la vérification | `/tmp/dsh-audit-ux/verification-citations.txt` |
| Empreintes du dépôt avant/après | `/tmp/dsh-audit-ux/empreinte-{avant,apres}.txt` |

Les avis bruts et le référentiel vivent dans `/tmp` : ils ne sont **pas** versionnés, pour ne
pas ajouter au dépôt un corpus qui vieillira. Ils peuvent l'être sur demande
(`packages/dsh-remote-swift/audit/`), et ne contiennent aucun secret ni identifiant réel.

Le référentiel HIG a été construit en interrogeant les **pages Apple elles-mêmes** — les
pages HTML étant rendues côté client, le contenu a été lu par les points d'entrée JSON de
`developer.apple.com`. Il couvre : Liquid Glass et matériaux, barres d'outils, Dynamic Type,
accessibilité (cibles, contraste, Reduce Motion), macOS (Réglages, menus, fenêtres, menus
contextuels), iOS (gestes, feuilles, haptique, écran de lancement, icône), vie privée et
manifeste de confidentialité, internationalisation — et il distingue explicitement ce qui
est écrit par Apple de ce qui n'est qu'interprétation. C'est lui qui a permis de trancher les
divergences du § 6, notamment sur le verre dans la couche de contenu.

**Ce que ce rapport ne dit pas.** Il ne juge pas le protocole ni la sécurité du plugin
`dsh-remote` (hors périmètre), il ne mesure aucun rendu, et il ne garantit aucune
conformité App Store : l'application n'est ni signable ni soumise en l'état, et plusieurs
constats « bloquants » du panel ne le sont que pour une soumission — le seul bloquant
**réel**, ici, est le premier lancement sur un iPhone neuf (§ 3.1).

---

## 10. État après les correctifs P0

Le plan du § 5 a été exécuté. Ce qui a changé, et la preuve qui l'accompagne :

| Point du P0 | Ce qui a été fait | Preuve |
|---|---|---|
| B1 — le jeton insaisissable | le jeton vit **aussi** dans la feuille « Adresse », tenu à part du modèle jusqu'à l'appui puis engagé (`enregistrerJeton`) ; il se recale sur le jeton de l'adresse affichée quand celle-ci change | capture iPhone de `--adresse` : section « Jeton d'appareil », bouton « Coller », compte de caractères, puis les deux actions |
| B1 — le remède du `401` | le message nomme les deux écrans qui portent réellement le champ, et plus les Réglages qui n'en ont aucun depuis la refonte | test « Le remède d'un 401 mène à un champ qui existe » |
| E6 — les étapes 3 et 4 inatteignables | le verrou reste un repère d'ordre (grisé, cadenas, « après l'étape N ») mais chaque étape non franchie porte son explication et un bouton « Voir la méthode » ; la règle est une fonction pure, `EtapesServeur.presentation` | capture iPhone de `--ajout --page-seule` ; test « Aucune étape d'une liste de travail n'est un cul-de-sac » |
| B2 — le MagicDNS en clair conseillé à tort | le conseil LIT l'Info.plist du paquet en cours (`ExceptionATS`) : sans exception il propose `https://…` ou le script qui pose l'exception ; avec elle il propose `http://` et le dit. L'adresse littérale n'est plus conseillée — mesuré, elle ne répond pas (`http://100.x.y.z:3080` → `000`) | 6 tests sur `ConseilAdresse` et `ExceptionATS` ; capture iPhone du build avec exception |
| A2 — VoiceOver muet | une phrase par ligne de session, par étape et par machine ; les indicateurs décoratifs sont masqués | 6 tests, dont un sur la distinction des cinq états |
| A3 — Réduire les animations ignoré | l'indicateur relit le réglage et s'arrête net ; les quatre carrés restent affichés | `EtatSession.anime` éprouvé ; le rendu demande un appareil |
| A4 — cibles tactiles | `cibleTactile()` — 44 pt et `contentShape` — sur copier, coller, effacer un jeton, envoyer, interrompre, effacer la recherche | un seul modificateur, donc une seule règle |

**Ce qui reste ouvert** : A1 (Dynamic Type complet), A5, A6, tout P1 (brouillon par
session, jeton lié à la machine affichée, journal honnête, états vides), P2 (gestes,
macOS), P3, P4 — et les vérifications du § 8, qui demandent un appareil.

**Une correction apportée au rapport lui-même.** Le § 3.2 proposait de conseiller
l'**IP littérale** (`http://100.x.y.z:3080`), en s'appuyant sur une section du README
aujourd'hui périmée. La mesure faite pendant les correctifs la contredit : le harness
n'écoute que sur la boucle locale, et rien ne répond sur l'IP du tailnet avec un port
(`000`), là où le nom MagicDNS publié par `tailscale serve` répond (`404`). Le remède
retenu est donc le second du § 3.2 — HTTPS pour supprimer le besoin d'exception —, plus
un conseil qui s'adapte au paquet au lieu d'affirmer.

