# dsh-remote-swift — client Swift multiplateforme

Client **Swift natif** (macOS et iOS) du plugin [`dsh-remote`](../../plugins/dsh-remote/).
Une seule bibliothèque partagée porte le protocole, le transport et les modèles ; les
deux applications la consomment telle quelle.

MISE À JOUR — jalons 2, 3 et l'écriture livrés : voir [Application](#application),
[Flux temps réel](#flux-temps-reel) et
[Écriture](#ecriture-repondre-a-l-agent-et-l-interrompre).

---

## Application

```bash
swift run DSHRemoteMac     # macOS : lit le jeton tout seul, aucune saisie
```

**Observé** dans une fenêtre 1100×720 : Tailscale connecté, les serveurs du tailnet,
et l'arbre des sessions groupé par espace de travail — la même vue que sur iPhone.
Cette commande a été remise en état de marche : elle était devenue fausse après la
restructuration (voir « Restructuration imposée par cette contrainte »).

L'application réutilise **exactement** la bibliothèque du tool : les vues ne parlent
jamais au réseau, elles observent `ModeleApp`. Remplacer le transport ne demande donc
aucune retouche d'interface.

### Où vit quoi : cinq pièces, et une seule porte sur le disque

`ModeleApp` portait **2 198 lignes et 66 états** : l'état observable, les transitions,
l'orchestration réseau, les trois boucles, la persistance, le trousseau et la lecture du
coffre. Quatre tranches en sont sorties, chacune avec ses tests — et `ModeleApp` fait
aujourd'hui **1 867 lignes**.

| Fichier | Ce qu'il porte | Ce qu'il ne fait pas |
|---|---|---|
| `ModeleApp` | l'état observable, les transitions, les règles qui les entourent | parler HTTP, écrire sur disque, lire le trousseau |
| `Connexion` | **comment** on parle à une machine : quels appels, quels délais, dans quel ordre | garder un état |
| `Sonde` | poser LA question (« sers-tu DSH ? ») et rassembler le verdict **et ses causes** | décider s'il faut publier le verdict |
| `Persistance` | ce qui survit à l'application : adresse, préférences, amorçage, diagnostic | connaître le réseau |
| `Jeton` | **où** le jeton est gardé (trousseau, mémoire) et **où** on le trouve (coffre) | décider lequel envoyer |
| `ClientDSH` | le PORT : les sept appels que le modèle utilise réellement | être un miroir de `RemoteClient` |

POURQUOI CES DÉCOUPAGES ONT ÉTÉ FAITS, ET PAS PAR GOÛT. Deux règles de la politique de
connexion avaient coûté cher sans être vérifiables — un plafond unique de huit secondes qui
a refusé une connexion valide après **8055 ms**, et l'ordre des deux questions qui décide
qu'on échoue en cinq secondes ou en trente-cinq. La fabrique de clients s'injecte : les
tests **voient le délai demandé pour chaque appel**, ce que le réseau ne permettait pas
d'observer. Ces pièces sont passées de **zéro test à quinze**.

### Voir ce que fait l'application : les traces s'allument à la demande

Une application lancée depuis le Dock n'a pas de terminal, et ses lignes de mesure étaient
donc écrites dans le vide — ou pire, lues comme du bruit. Elles sont **éteintes par défaut**
et se rallument d'un mot :

```bash
DSH_REMOTE_TRACE=1 "/Applications/DSH Remote.app/Contents/MacOS/DSHRemoteMac"
```

Quatre mesures de cette session en sont venues : le verdict de la sonde (16 à 183 ms), la
durée d'une connexion (**23,7 s** sur un harness fraîchement redémarré, contre 4,3 s à
chaud), la liste reçue de l'hôte, et l'oscillation d'adresse entre deux machines — celle qui
a révélé que « choisi » et « visé » étaient cinq champs écrits par dix-sept endroits.

Vérifié : **0 ligne** sans la variable, les quatre traces avec.

Une seule structure d'interface sert les deux plateformes : `NavigationSplitView`, que
SwiftUI replie en pile sur iPhone. La seule différence réelle est la provenance du jeton
— coffre du harness sur le Mac, trousseau sur iPhone — et elle est confinée à `ModeleApp`.

### iPhone : deux points à connaître

1. **Le jeton doit être saisi une fois.** Il n'est pas dans un fichier sur iOS. Pour
   l'obtenir sans le faire passer par l'écran du Mac :

   ```bash
   python3 -c "import re,os;print(re.search(r'token: *([A-Za-z0-9_-]{20,})',open(os.path.expanduser('~/.dsh/.credentials.yaml')).read()).group(1))"
   ```

   Il est ensuite conservé au trousseau (`kSecAttrAccessibleAfterFirstUnlock`), jamais
   dans les préférences.

2. **Utiliser l'adresse tailnet en chiffres, pas le nom MagicDNS.** App Transport
   Security n'impose TLS qu'aux noms de domaine qualifiés ; une adresse IP littérale en
   est exemptée. Passer par le nom MagicDNS demanderait une exception ATS dans le projet
   Xcode — donc un `Info.plist` et un projet, ce que ce paquet SwiftPM n'a pas encore.

   ```bash
   tailscale ip -4        # sur le Mac : 100.x.y.z
   ```

   L'adresse est ensuite `http://100.x.y.z:3080`. Tailscale chiffre le trajet de bout en
   bout (WireGuard) ; `tailscale serve` publie en HTTP, il n'y a donc pas de TLS à
   attendre et aucune exception ATS n'est nécessaire.

### Essai sur le simulateur iOS — fait, et ce qu'il a appris

L'application a été **lancée et observée** dans le simulateur iPhone 17 Pro (iOS 26.2),
connectée à la véritable instance DSH : elle affiche **48 sessions vivantes** avec leurs
titres, projets, compteurs d'événements et volumes. Trois faits en sont sortis, chacun
contredisant une hypothèse raisonnable :

1. **Le simulateur partage la pile réseau du Mac *et* sa boucle locale.** Il atteint
   `http://127.0.0.1:3080` — donc le harness — mais **pas** l'adresse tailnet du Mac
   (`100.x.y.z`), qui n'est pas routeable depuis le simulateur. Un essai sur simulateur
   ne prouve donc rien du chemin tailnet.
2. **Les surcharges par variable d'environnement n'arrivent pas à une application iOS.**
   `simctl launch` place ses arguments additionnels dans `argv`, pas dans
   l'environnement : `ProcessInfo.environment` ne les voit pas. `DSH_REMOTE_ADRESSE` et
   `DSH_REMOTE_COFFRE` sont donc inopérants sur iOS — utiles seulement sur macOS.
3. **Aucun compte développeur Apple n'est configuré** sur cette machine : zéro identité
   de signature, zéro profil de provisionnement. Le code compile pour l'iPhone réel
   (`swift build --triple arm64-apple-ios18.0`), mais **rien ne peut être signé ni
   installé sur l'appareil** sans ton identifiant Apple.

### Amorce par fichier — pour essayer l'application

Puisque l'environnement ne traverse pas, l'application lit au démarrage une
configuration déposée dans **son propre conteneur** :

```json
{ "adresse": "http://127.0.0.1:3080", "jeton": "…" }
```

Chemin : `Documents/dsh-remote-config.json`. Sur un simulateur, on l'y dépose depuis le
Mac :

```bash
DOCS=$(xcrun simctl get_app_container <device> org.example.dsh-remote data)/Documents
```

**Portée réelle : nulle en production.** L'application ne crée jamais ce fichier ; il
faut le déposer explicitement dans un conteneur. Sur un iPhone réel, rien ne le lit — le
jeton vient alors du trousseau, après une saisie unique.

### Découverte des serveurs : ce qui est possible, et la voie retenue

J'ai d'abord écrit que « la découverte est impossible sur iPhone ». **C'était trop
absolu** — vrai de la méthode que j'avais choisie, faux comme conclusion. Une
application iOS ne peut pas lancer `tailscale status`, et le socket LocalAPI de
l'application Tailscale n'est pas lisible depuis un autre bac à sable ; mais cela
n'épuise pas les moyens praticables.

**Trois voies, par ordre de qualité :**

1. **Le Mac découvre, l'iPhone consomme — VOIE RETENUE, ET LIVRÉE.** Une instance DSH
   sait déjà voir le tailnet : elle a le binaire. Le plugin publie donc la liste des
   Macs qu'il voit (`GET /dsh-remote/v1/serveurs`), et l'application la consomme. Zéro
   dépendance à une API Apple ou à une permission Tailscale : l'iPhone ne découvre
   rien, il LIT une découverte faite ailleurs. C'est la seule voie qui donne une liste
   exacte et à jour.
2. **Balayer des noms candidats.** Le domaine du tailnet se déduit de l'adresse
   que l'utilisateur a déjà saisie ; il ne reste qu'à tester des noms plausibles.
   Fonctionne, mais devine, et le nom d'une machine renommée est introuvable.
   **Non implémentée** : la voie 1 rend la liste exacte, deviner n'ajoute rien.
3. **Se souvenir de ce qui a marché.** Une liste de serveurs connus, réutilisable
   et testable d'un appui. C'est le complément naturel de la voie 1, et il
   fonctionne même hors ligne. **Partiellement en place** : l'adresse ET le nom du
   dernier serveur sont mémorisés, mais il n'y a pas encore de liste de plusieurs
   serveurs connus.

### Ce qui est livré pour la découverte

| Élément | Où |
|---|---|
| L'hôte découvre et publie la liste | `GET /dsh-remote/v1/serveurs` (plugin) |
| Le client la lit | `RemoteClient.listerServeurs()` |
| Le modèle la consomme | `ModeleApp` : après une connexion réussie, si `capacites.decouverte` |
| L'ordre des sources | hôte joint d'abord, Tailscale local (`macOS`) seulement en son absence |
| La liste s'affiche avec icône, état, et « hôte interrogé » | `VueListeSessions` |
| Une liste vide dit POURQUOI | `ModeleApp.messageListeVide`, qui distingue « l'hôte ne voit personne » de « cette plateforme ne peut pas voir » |
| Le tout est éprouvable sans interface | `dsh-remote-ctl <adresse> serveurs` |

**Ce que la voie 1 a demandé, et qui ne se devinait pas.** Côté hôte, le CHEMIN du
binaire Tailscale décide du succès : `/usr/local/bin/tailscale` est un lien symbolique
vers le binaire de l'application, et par ce lien le CLI échoue (« The current
bundleIdentifier is unknown to the registry ») alors que le chemin direct rend l'état
complet du tailnet. La découverte essaie donc ses candidats jusqu'à un **succès**, et
non jusqu'au premier fichier exécutable.

**UN CODE DE SORTIE NUL NE PROUVE RIEN, ET C'EST UN DÉFAUT QUI A ÉTÉ VU À L'ÉCRAN.**
Lancé depuis une application ouverte par le **Finder**, le CLI Tailscale n'arrive pas à
joindre son application et écrit :

```
code=0   stdout=105 octets
The Tailscale GUI failed to start: The operation couldn't be completed. (Tailscale.CLIError error 3.)
```

L'erreur part sur **stdout**, pas sur stderr, et le code de sortie vaut **0**. La
découverte lisait « code 0 = succès », l'analyse ne trouvait pas de JSON et rendait `[]`,
et l'application annonçait « aucun Mac macOS dans le tailnet » — un mensonge sur l'état du
tailnet, alors que c'était le CLI qui n'avait pas parlé. Pire : la boucle des candidats
s'arrêtait là, avant `~/.local/bin/tailscale`, **qui répond dans ce même environnement**.

Le correctif tient en une règle : **exiger un état lisible**, pas un code de sortie. Un
état Tailscale porte `Self` ; sans lui, ce n'est pas un tailnet vide, c'est une réponse
qui ne dit rien — et le candidat suivant est essayé. Mesuré, même code et même machine :

| Environnement | Avant | Après |
|---|---|---|
| Terminal | 3 Macs | 3 Macs |
| Environnement d'application (Finder) | `aucun Mac decouvert` | **3 Macs** |

Le plugin hôte n'a jamais eu ce défaut : en JavaScript, `JSON.parse` **lève**, donc la
route essaie le candidat suivant et rapporte « sortie illisible ». C'est le code Swift qui
se fiait au code de sortie.

**Résultat mesuré** : sur le simulateur iPhone 17 Pro, la liste des Macs du tailnet
s'affiche — trois machines, avec icône, état en ligne/hors ligne, et la mention « hôte
interrogé » sur celle qui répond. L'application n'exécute aucun processus : elle lit la
réponse de l'hôte. Sur le Mac, l'application empaquetée lancée dans un environnement
d'application trouve les **3 mêmes Macs** et sonde lesquels servent DSH (`1 serveur(s) DSH
sur 3` — les deux autres n'ont rien qui écoute, ou sont hors ligne).

### Une machine éteinte n'est pas une panne réseau

**Le défaut, vu à l'écran.** L'application mémorise le dernier serveur utilisé et s'y
reconnecte au lancement. Le propriétaire avait choisi un MacBook Pro ; ce Mac s'est
éteint ; à chaque ouverture, l'application lançait donc une requête vers une machine
morte, **attendait 21 secondes** (mesuré : `dsh-remote-ctl http://<ce-mac> sante` →
`real 0m21.021s`), puis affichait :

> échec de transport : NSURLErrorDomain -1001 … | CAUSE: délai dépassé, hôte injoignable

Un message **technique**, pour une machine dont le même écran affichait déjà « hors
ligne », trois lignes plus haut. Le garde-fou `ajusterAuParc` bascule bien sur un Mac en
ligne — mais seulement si la liste est **déjà chargée** : la requête de 21 s était partie
avant. Deux autres gestes inutiles allaient avec : la sonde interrogeait aussi les
machines éteintes (`3 candidat(s)` dont un Mac éteint depuis des mois), et l'erreur
survivait à la bascule, accusant le réseau alors que l'application avait repris ailleurs.

**La règle retenue** : l'état connu prime sur la tentative. Une machine que la liste dit
hors ligne n'est pas visée, et n'est pas sondée ; son message dit l'état et l'action
(« allumez-le, ou choisissez un Mac en ligne »), jamais le réseau. Une adresse **saisie à
la main** reste tentée : on ne peut rien affirmer d'une machine qu'on n'a pas vue.

Mesuré sur l'application installée, lancée comme le Finder la lance, l'adresse mémorisée
pointant toujours sur le Mac éteint :

| | Avant | Après |
|---|---|---|
| Sonde | `3 candidat(s)` — dont la machine morte | **`2 candidat(s)`** |
| Fichier de diagnostic | réécrit avec un `-1001` après 21 s | **inchangé** (aucune requête émise) |

#### Le statut ne reste plus sur « vérification… »

**Symptôme rapporté** : les Macs **en ligne** restaient sur « vérification… », alors que le
Mac éteint, lui, affichait correctement « hors ligne ».

**Cause** : la sonde lançait ses requêtes en groupe et attendait **toutes** les réponses —
y compris celle de la machine morte, qui ne répond jamais. Le verdict des machines saines
était donc retenu en otage par une machine éteinte. La correction est celle du paragraphe
précédent : on ne sonde plus ce qui ne peut pas répondre.

Mesuré sur la version corrigée, dans le simulateur : « **DSH · hôte** » sur le Mac qui
sert DSH, « **pas de DSH** » sur celui qui est en ligne sans rien publier, « **hors
ligne** » sur l'éteint.

**LE VERDICT NE REPASSE PLUS PAR « vérification… » À CHAQUE RAFRAÎCHISSEMENT.** La sonde
est relancée toutes les quinze secondes, et elle remettait `sondageEffectue` à zéro en
commençant : les légendes redevenaient « vérification… » le temps de la sonde, et l'écran
semblait ne jamais conclure — photographié deux fois par le propriétaire, alors que la
sonde rendait son verdict en moins d'une seconde. Un verdict **connu** reste affiché
pendant qu'on le rafraîchit ; il n'est « inconnu » que tant qu'il n'y en a jamais eu.
Vérifié par une capture prise *pendant* une sonde : les trois légendes restent stables.

**ET UN ÉCHEC DEVENU FAUX DISPARAÎT.** Le message « Aucun service ne répond sur le port
80 de ce Mac », avec ses commandes, restait affiché après que la commande avait été passée
sur l'autre Mac : rien ne rejouait la connexion, et il fallait appuyer de nouveau sur la
machine pour s'en apercevoir. La sonde, elle, le sait — elle vient de l'interroger. Quand
son verdict contredit l'erreur affichée, l'erreur s'efface et la connexion est retentée
(`relancerSiLaCibleSertDsh`).

#### Combien de temps prend « la vérification » : mesuré

La question « pourquoi est-ce si long ? » méritait une mesure, pas une explication. Tout
est en millisecondes :

| Étape | Coût mesuré |
|---|---|
| Découverte locale (`tailscale status --json`) | **44 ms** |
| Sonde complète, du `debut` au `fin` | **16 ms** (0,289 s → 0,305 s après le lancement) |
| Requête vers la boucle locale | 1,2 ms |
| Requête vers un Mac du tailnet (`tailscale serve`) | 6,4 ms |
| Requête vers MacMini (qui répond `404`) | 15 ms |

**Le verdict est donc posé moins de 0,3 s après le lancement.** Ce qui donnait
l'impression du contraire était la remise à zéro décrite ci-dessus : toutes les quinze
secondes, la légende redevenait « vérification… » le temps de la sonde. Une sonde de
16 ms, répétée, suffisait à ce qu'un coup d'œil tombe dessus — et l'écran semblait ne
jamais conclure. Depuis, un verdict connu reste affiché.

**LE SEUL CAS OÙ LA SONDE EST VRAIMENT LENTE** est une machine **en ligne sur le tailnet
mais qui ne répond rien** (ni accord, ni refus) : la requête attend alors le délai de
2,5 s, et le groupe attendant tous ses membres, le verdict des machines saines est
retardé d'autant. C'est une attente bornée, et le prix de ne pas conclure trop vite.

#### Un port 80 occupé par autre chose n'est pas un port vide

Mesuré après coup, sur MacMini : il ne renvoie plus `-1004` mais **`HTTP/1.1 404 Not
Found`**, sans en-tête `Server` — la signature de `tailscale serve` actif mais ne publiant
pas DSH. L'application affichait alors « réponse inattendue (HTTP 404) », un code
technique pour une situation qui a une explication et un remède.

Les deux cas sont donc reconnus (`repondMaisPasDsh`), et le **texte les distingue** :

| Constat | Message |
|---|---|
| `-1004` — rien n'écoute | « Aucun service n'écoute sur le port 80 de ce Mac. Le tailnet, lui, fonctionne : la machine répond. » |
| `404` (ou autre statut inattendu) — autre chose écoute | « Ce Mac répond, mais pas DSH : son port 80 est occupé par autre chose, ou `tailscale serve` n'y publie pas l'instance. » |

La classification ne cherche plus un code dans un texte d'erreur : l'erreur est **gardée
en type** (`erreurType`), parce que la recherche textuelle avait précisément raté ce
`404`. Les deux cas montrent les mêmes commandes copiables.

#### Un seul écrivain par état — et une génération pour les réponses en vol

Les trois boucles (suivi 3 s, serveurs 15 s, flux) et les actions de l'utilisateur écrivaient
dans le modèle **sans que rien ne relie une réponse à la cible qui l'avait demandée**. Une
réponse partie vers l'ancienne machine peut arriver **après** une bascule : l'écran
afficherait alors les sessions d'un serveur sous le nom d'un autre, sans que rien ne le
signale.

Deux règles, désormais tenues par la structure :

1. **Chaque collection a un écrivain nommé** (`appliquerSessions`, `appliquerJournal`,
   `appliquerEspaces`, `appliquerServeursDuTailnet`, `appliquerServeursDeLhote`). Un `grep`
   le vérifie : plus aucune écriture directe ailleurs, sauf les remises à zéro explicites.
2. **Un compteur de génération** est incrémenté à chaque changement de cible — dans `viser`,
   le seul endroit qui remplace la cible. Chaque départ d'une réponse asynchrone retient la
   génération, et chaque écrivain la vérifie : une réponse qui décrit l'ancienne machine est
   **refusée**.

La liste des machines du **tailnet** échappe délibérément à la garde : c'est un fait du
tailnet, pas une donnée d'un serveur, et la jeter parce que la cible a bougé viderait la liste
au moment précis où l'utilisateur choisit une machine.

**2 tests** éprouvent la règle : changer de cible invalide les réponses déjà parties, et une
liste arrivée en retard n'écrase pas la nouvelle. Écrits, ils ont d'ailleurs attrapé une
erreur de ma part : le résumé d'une session est **aplati** dans l'objet par le plugin, et ma
fixture l'imbriquait — l'identifiant décodé était « (inconnu) ».

**DEUX LECTURES DU MÊME CONTENU.** Le propriétaire a tranché : « en fait les
étapes pour la page détail, c'est un diagnostic de santé ». Sur la page d'un
serveur, les quatre lignes **constatent** l'état d'une machine — on veut tout
savoir d'un coup, rien n'est verrouillé, et chaque étape non franchie porte sa
méthode. Sur la page « Ajouter un serveur », elles **listent** un travail à faire,
dans l'ordre.

| Page | Lecture | Verrou |
|---|---|---|
| un serveur | **diagnostic de santé** | aucun : un diagnostic qui cache la moitié de ses conclusions n'en est pas un |
| « Ajouter un serveur » | **objectifs à réaliser** | les étapes suivant celle qui bloque sont grisées |

Le diagnostic s'ouvre sur sa **conclusion** — « Ce serveur est prêt. » / « Il reste
une étape : « … » » / « Vérification en cours… » — parce que « ce serveur est-il
utilisable ? » est la question, et les quatre étapes la démonstration. Le titre de
l'étape restante est **cité tel quel** : le mettre en minuscules abîmait les noms
propres (« Ce Mac est visible » devenait « ce mac est visible », constaté sur
capture).

**UNE SEULE FRONTIÈRE À LA FOIS.** Demande du propriétaire : « si une étape de goal
n'est pas réalisée, les goals suivants sont grisés (pas besoin de rentrer dans leur
détail) ». Le parcours affiche donc :

- les étapes **franchies** : leur titre, et rien d'autre ;
- la **première non franchie** : son explication et sa méthode — c'est elle qu'on
  peut faire maintenant ;
- les **suivantes** : grisées, avec un cadenas et la mention « après l'étape N »,
  sans explication ni commande. Leur mode d'emploi suppose la précédente franchie ;
  l'afficher noierait celle qui bloque.

C'est une conséquence de l'ordre : on ne publie pas un port sur un Mac qui n'est pas
sur le réseau, et on n'installe pas un plugin derrière un port fermé. La règle vit
dans `EtapesServeur.estVerrouillee` (éprouvée), et la mise en page dans
`ParcoursDesEtapes`, **partagée** par les deux pages.

#### La page « Ajouter un serveur » : le même parcours, pour un Mac qu'on n'a pas encore

La vignette **« Ajouter »** du carrousel menait à une **recherche**. Sur un iPhone
où rien n'est encore installé, elle ne pouvait donc rien trouver et n'apprenait
rien : ni ce qui manque, ni sur quelle machine, ni dans quel ordre. Le
propriétaire a demandé qu'elle mène à la page de détail, « pour leur dire les goals
à réaliser ».

Elle ouvre donc une page qui liste le travail à faire pour qu'un Mac devienne un
serveur — **le même parcours que la page d'un serveur**, à une différence près :
là-bas on JUGE une machine connue, ici on liste le travail pour un Mac qu'on n'a
pas encore.

| Étape | Ce qu'elle dit |
|---|---|
| 1. Tailscale est connecté sur cet appareil | **constaté** : c'est la seule des quatre qu'on puisse mesurer d'ici |
| 2. Le Mac à ajouter est sur le tailnet | sur ce Mac-là : installer Tailscale, le connecter, `tailscale status` |
| 3. Le port de DSH y est ouvert | sur ce Mac-là : `tailscale serve --bg --http=80 http://127.0.0.1:3080` |
| 4. Le plugin `dsh-remote` y est installé | la même démarche que la page d'un serveur |

Les commandes disent **sur quelle machine les taper** — l'étape 1 concerne cet
appareil, les autres le Mac à ajouter. La recherche reste offerte DANS la page
(c'est la seule façon de redemander sa liste à l'hôte, sur iPhone), ainsi que la
saisie manuelle d'une adresse.

**DEUX PROCÉDURES PARTAGÉES.** « Publier le port » et « installer le plugin »
vivent maintenant dans `Demarches.swift`, utilisées par les deux pages : le travail
à faire sur le Mac est identique, et deux copies auraient divergé — l'utilisateur
les compare.

**UN DÉFAUT CORRIGÉ EN CAPTURANT.** `tailnetDeLAppareil` valait `false` par défaut,
donc « pas encore mesuré » s'affichait comme « à faire » : le parcours affirmait que
Tailscale n'était pas connecté alors que le Mac l'était. L'état est devenu
**tri-état** (`Bool?`), et l'ancre de vérification mesure avant d'afficher — elle
court-circuite le démarrage, donc rien n'était constaté.

#### Le parcours d'un serveur : trois étapes, et la méthode pour chacune

Demande du propriétaire : « une ligne de goal à franchir », avec, pour chaque
étape non remplie, la méthodologie pour y arriver. La page d'un serveur montre
donc un **parcours** — et non plus seulement un diagnostic.

| Étape | Ce qu'elle veut dire | D'où vient son état |
|---|---|---|
| 1. Tailscale est connecté sur cet appareil | il porte une adresse de tailnet | une CONSTATATION locale : `getifaddrs`, plage `100.64.0.0/10` |
| 2. Ce Mac est visible | il est en ligne sur le tailnet, donc la découverte le propose | un FAIT de Tailscale (`Online`), lu, jamais mesuré par l'application |
| 3. Le port de DSH est ouvert | quelque chose répond sur son port 80, publié par `tailscale serve` | la sonde : un `404` prouve que le port est ouvert |
| 4. Le plugin `dsh-remote` est installé | DSH Remote y répond | la sonde : `200` ou `401` |

**LA PREMIÈRE ÉTAPE A ÉTÉ AJOUTÉE APRÈS COUP**, à la demande du propriétaire :
« j'ai oublié un goal avant, le fait que Tailscale est connecté ». Elle manquait
effectivement — sur un iPhone sans Tailscale, les trois autres ne peuvent pas être
franchies, et le parcours commençait pourtant par elles. Quand elle n'est pas
franchie, **les suivantes passent à « inconnue »** : une liste de machines peut
dater d'avant la coupure, et une sonde avoir répondu il y a une minute — affirmer
quoi que ce soit depuis un appareil qui ne peut plus rien joindre serait parler du
passé.

**ON N'ACCUSE LE PLUGIN QUE SI QUELQU'UN A RÉPONDU.** Un `404` prouve que le port
est ouvert, donc que ce qui manque est le plugin. Port fermé, ou échec
inexpliqué : le plugin est peut-être installé, et on le dit — la version
précédente le déclarait « à faire » dans tous les cas, ce qui envoyait installer
un plugin derrière un port fermé.

**ARTEFACT DE SIMULATEUR, ÉCRIT POUR NE PAS TROMPER.** Dans le simulateur iOS,
l'appareil partage les interfaces du Mac : l'étape 1 y apparaît donc toujours
franchie, alors que Tailscale n'y est pas installé. Sur un vrai iPhone sans
Tailscale, elle passe bien à « à franchir » — c'est la logique qu'éprouvent les
tests, pas la capture.

**CE QU'ON MONTRE QUAND ON NE SAIT PAS.** Trois états par étape : franchie, à
franchir, ou **inconnue**. Une machine hors ligne ne dit rien de son port : on
n'envoie donc personne publier un port sur un Mac éteint, et la ligne porte
« à vérifier » avec la commande de CONSTAT (`tailscale serve status`) plutôt
qu'avec la méthode complète. De même, une erreur qui n'explique rien (délai, DNS)
ne fait pas conclure que le port est fermé.

**ON N'OUTILLE QUE CE QUI RESTE.** Une étape franchie n'affiche ni explication ni
commande : elles noieraient celle qui bloque. Et parmi les étapes non franchies, seule la
PREMIÈRE porte sa méthode dépliée : c'est la seule exécutable maintenant, les autres
supposent la précédente franchie. Leur marche à suivre existe toujours, derrière
« Méthode » — trois jeux de commandes à l'écran noyaient celle qui compte.

**UNE EXPLICATION SUIT SON ÉTAT.** Les quatre explications étaient écrites au présent de
l'étape FRANCHIE, et les deux copies de la liste — appareil hors tailnet, machine jugée —
les répétaient telles quelles. Sur un Mac éteint, la page lisait donc, sous un titre
déclarant l'étape « à faire » : « Il est en ligne sur le tailnet, donc la découverte le
propose ». Constaté sur capture, et signalé par le propriétaire : « l'étape 2 si le serveur
est off-line, le message doit le prendre en compte ». Une explication qui contredit son
propre état fait douter du diagnostic entier, et envoie chercher au mauvais endroit.

Les textes vivent maintenant dans une **fabrique unique** (`EtapesServeur.etape(_:_:)`), que
les deux sorties de `etapes(...)` partagent — c'était la duplication qui avait laissé la
phrase fausse à deux endroits. Trois formes, une par état : pour une étape **franchie**, ce
que l'état EST ; pour une étape **à faire**, le constat INVERSE, sans la marche à suivre (la
méthode s'affiche juste en dessous, et l'écrire deux fois dilue celle qui compte) ; pour une
étape **inconnue**, ce que l'étape DEMANDE, puisqu'on ne peut rien constater. Deux tests
l'éprouvent : sur l'étape 2 hors ligne, sur l'appareil hors tailnet, et sur les étapes 3 et
4 quand c'est le port ou le plugin qui manque.

Vérifié par capture, sur les deux cas qui comptent : MacMini (port ouvert, plugin
absent → étapes 1 et 2 vertes, étape 3 à faire avec le bloc `cordis.patch.yml` à
copier) et un Mac hors ligne (étape 1 à faire avec `tailscale status` / `tailscale
up`, les suivantes « à vérifier »).

8 tests couvrent le calcul des états, dont les quatre cas d'ignorance.

#### Quand la machine répond mais n'a pas le plugin : le dire, et donner la démarche

Demande du propriétaire : « il faut dire dans remote que le plugin n'est pas installé et
donner la démarche ». Deux choses, donc — un CONSTAT nommé, et une PROCÉDURE.

Le cas mesuré sur MacMini : son port 80 est publié (la racine répond « dsh web authentication
required »), mais `/dsh-remote/v1/sante` rend **404**. Ce n'est ni le tailnet, ni
`tailscale serve`, ni le jeton : c'est le plugin qui n'y est pas chargé. La page l'annonce
ainsi, puis donne les trois étapes :

1. avoir le dépôt `dsh-plugins` sur ce Mac, et y prendre `plugins/dsh-remote` ;
2. le **déclarer** dans `~/.dsh/profiles/web/cordis.patch.yml` — le bloc YAML se copie d'un
   appui, avec `CHEMIN/DU/DEPOT` en espace réservé (sur l'autre Mac, le dépôt n'est pas au
   même endroit, et un chemin d'exemple recopié tel quel échouerait sans dire pourquoi) ;
3. **relancer** le harness — ici `dsh web`. Le code d'un plugin n'est pas rechargé à chaud :
   sans redémarrage, l'ancien processus continue de répondre.

Et la vérification qui marche **sans jeton** : `curl` sur `/dsh-remote/v1/sante` rend **401**
quand aucun jeton n'est présenté, **200** quand il l'est. Les deux prouvent que le plugin est
chargé — ce qui est la question. Mesuré sur cette machine.

##### Le diagnostic appartient à la MACHINE, pas à la connexion

DÉFAUT TROUVÉ EN VÉRIFIANT. Le bloc de diagnostic lisait l'erreur de la **connexion en
cours** : sur la page de MacMini alors que l'application était connectée ailleurs, il n'y
avait donc **aucun remède** — et connecté à MacMini, il pouvait en afficher un qui parlait
d'une autre cause. La cause est maintenant une valeur attachée à la machine :

- la **sonde** retient, pour chaque machine qui ne sert pas DSH, la cause observée (`404` →
  plugin absent, `-1004` → rien n'écoute) ;
- la page rend cette cause-là pour la machine qu'elle montre, et la mesure de la connexion
  seulement si c'est bien elle qu'on visait.

`--serveur=<fragment>` est l'ancre de vérification correspondante : elle ouvre la page d'une
machine **nommée**, ce qui est le seul moyen de capturer le cas d'une machine à laquelle on
n'est PAS connecté. Elle a d'ailleurs révélé un second défaut : avec `--page-seule`, le
panneau latéral n'existe pas, donc l'ancre `--serveur=` qui y vivait ne s'exécutait jamais, et
la capture montrait le MacBook Air quand on avait demandé MacMini. La résolution de la machine
est désormais **la même** pour les deux formes.

##### Une régression que j'ai introduite, et que le test tient

En rendant le jeton « par hôte », j'ai fait que `jetonDeLaCible()` ne consultait plus le champ
de saisie — seulement le gardien et le coffre. Or le champ porte la valeur la PLUS FRAÎCHE.
Résultat mesuré : l'application démarrait en **0 ms** sans rien tenter, avec « aucun jeton »
alors que le champ en contenait un. Le champ est désormais consulté en premier, et un test le
verrouille (« le jeton du champ est utilisé, même sans liste de machines ni gardien »).

#### Le jeton est gardé PAR HÔTE — et le coffre local ne parle que de la machine locale

Le jeton d'appareil est tiré par **chaque** hôte (mesuré). Le client n'en gardait pourtant
qu'un, sous un compte de trousseau unique : il fallait donc le recoller à chaque bascule, et
l'oublier revenait à envoyer à une machine le secret d'une autre.

Désormais la clé de stockage **est l'adresse de l'hôte**, et le modèle parle à un
`GardienDeJetons` :

| Plateforme | Où le jeton vit | Pourquoi |
|---|---|---|
| iPhone | **trousseau**, une entrée par hôte | c'est fait pour ça, et cela survit au redémarrage |
| macOS | **mémoire**, par hôte | l'app est signée **ad-hoc** : un élément de trousseau est lié à la signature, donc une reconstruction changerait l'accès — au mieux une invite à chaque lancement, au pire un secret perdu |

**CONSÉQUENCE, DITE POUR ÊTRE VUE** : sur le Mac, le jeton d'un hôte **distant** est à recoller
après un redémarrage de l'application. Celui de l'hôte local n'a jamais à l'être — il vient du
coffre du harness, qui est sa source, et l'application **ne le recopie pas** : une seconde
copie d'un secret est une occasion de fuite de plus.

Et le coffre (`~/.dsh/.credentials.yaml`) n'est consulté **que si la cible est cette machine**.
Il contenait le jeton de l'hôte local, et rien d'autre : le proposer pour une autre machine,
c'était lui envoyer un secret qui ne lui était pas destiné.

#### Deux délais pour deux questions — et un plafond unique qui a menti

Un seul plafond de connexion existait (vingt secondes, la valeur par défaut d'`URLSession`).
Mesuré :

| Question | Durée réelle | Plafond retenu |
|---|---|---|
| « y a-t-il un DSH en face ? » (`sante`) | **4,1 / 3,2 / 1,6 ms** | 5 s |
| la liste des sessions | **4,06 s à froid**, puis 15 à 27 ms | 30 s |
| routes qui font travailler l'hôte (`/v1/serveurs`) | le CLI Tailscale y est borné à 8 s | 14 s |

**L'ERREUR QUE LA MESURE A ATTRAPÉE** : un plafond unique de huit secondes a été essayé
d'abord — et une connexion **parfaitement valide** a été refusée après **8055 ms**, parce que
la liste à froid prend 4 s et que le harness était occupé. L'application a annoncé un échec
pour un serveur qui répondait. Un plafond court ne protège de rien : il transforme une machine
occupée en machine en panne. Les deux questions ont donc deux délais, et après séparation la
même connexion réussit en **4269 ms**.

#### L'état du modèle : deux valeurs au lieu de huit champs

Le propriétaire a dit : « j'ai l'impression que le projet gère mal le state management ». Il a
raison, et l'inventaire le montre : **38 états stockés, ~127 écritures directes**, et surtout
des champs **corrélés** dont les combinaisons invalides étaient représentables.

| Ce qui coexistait | Ce que ça a produit, ici |
|---|---|
| `sondageEffectue` + `serveursAvecDsh` + `sondageEnCours` | verdict remis à zéro à chaque sonde (légendes qui clignotent), puis une sonde **annulée** qui écrit un faux « 0 DSH » |
| `erreur` (texte) + `erreurType` (type) + `capacites` + `etatAdresse` + `serveurJoint` | le texte et le type ont **divergé** : la classification par texte a raté le `404` de MacMini |
| `adresse` + `nomServeur` + `serveurChoisi` + `serveurJoint` + `serveurOuvert` | « choisi » et « ouvert » confondus → la vignette ne marquait pas la page lue |

**CE QUI A ÉTÉ FAIT — les deux premiers, mécaniquement et sans toucher aux vues :**

```swift
enum EtatSonde { case inconnue, enCours, connue(Set<String>) }
enum EtatConnexion {
  case inconnue, enCours, jointe(Sante, reponses: Int), echec(ErreurRemote)
  case incomplete(String)     // on n'a pas tenté, et CE N'EST PAS le jeton
  case jetonInvalide(String)  // le jeton manque, est tronqué, ou a été refusé
}
```

- **`EtatSonde`** rend inécrivable le « verdict vide + drapeau vrai » qui a produit le faux
  « 0 DSH » ; le verdict CONNU reste affiché pendant un rafraîchissement, parce que la sonde
  ne repasse par `.enCours` que si l'on ne savait rien.
- **`EtatConnexion`** remplace cinq champs. Le texte de l'erreur est **dérivé** de son type
  (`erreur`, `erreurType`), `etatAdresse` est une **vue** de la connexion, `capacites` et
  `serveurJoint` aussi : ils ne peuvent plus dire autre chose qu'elle. Le cas
  `.incomplete` distingue ce qui empêche de TENTER d'un échec réseau — le remède n'est pas au
  même endroit.
- **`.jetonInvalide` A ÉTÉ SÉPARÉ D'`.incomplete`, ET C'EST UN DÉFAUT MESURÉ.** Un seul cas
  portait les deux, et `jetonRefuse` le prenait en bloc : la page d'un Mac **éteint**
  affichait donc « Le service a refusé ce jeton. Collez celui de CET hôte » — deux
  avertissements de jeton en tête d'une page qui n'avait jamais rien joint, dont le remède
  était faux. Constaté sur capture. `.incomplete` garde ce qui n'est pas le jeton (« cette
  machine est hors ligne », une action locale en échec), `.jetonInvalide` ce qui se répare
  dans le champ. Un état qui mélange deux causes produit un remède faux.

**5 tests d'invariants** (77 au total) tiennent ces propriétés sans réseau, via deux crochets
compilés en `DEBUG` seulement : une sonde inconnue ne conclut pas, un verdict connu survit au
rafraîchissement, un verdict vide est un verdict, une erreur typée porte son texte, le test
d'adresse dérive de la connexion.

**Vérifié en vrai** : après le remaniement, l'application démarre et pose son verdict en
**0,4 s** (journal : `[sonde] debut` à 1,76 s, `fin : 1 serveur(s) DSH sur 2 en 80 ms`).

**PUIS LA CIBLE — cinq champs, dix-sept écritures, un seul écrivain désormais.**

Le « serveur courant » était éclaté en `adresse`, `nomServeur`, `serveurChoisi`, `echecCible`
et `choixAjuste`, écrits depuis dix-sept endroits. Le journal d'un démarrage réel montrait ce
que cela produit :

```
 1.44 s  adresse=http://macmini…
 5.34 s  connecter http://macbook-air… : 3578 ms
19.13 s  connecter http://macmini…     :   42 ms
```

L'adresse **oscillait** entre deux machines en vingt secondes, parce que la bascule, la
mémorisation et la reconnexion écrivaient chacune la sienne sans que personne ne voie
l'ensemble. Ces cinq champs sont maintenant **une valeur** (`Cible`), remplacée en **un seul
point** (`viser`), avec cinq transitions nommées pour y mener : `definirAdresse`, `choisir`,
`basculer`, `oublier`, `consigner`.

- **`consigner` ne construit pas de cible** : elle ne modifie que l'échec, donc elle ne PEUT
  pas déplacer la machine de l'utilisateur. C'était la règle la plus coûteuse à tenir.
- **`basculer` passe par `choisir`** : même transition que l'utilisateur, mêmes conséquences,
  plus l'avis qui dit pourquoi.
- La **page ouverte** (`serveurOuvert`) reste à part : regarder une machine n'est pas la
  viser, et les confondre a déjà produit un défaut.

Après ce remaniement, un démarrage réel ne montre plus qu'**une seule adresse** et une seule
connexion. 5 tests de plus (82 au total) éprouvent les transitions **sans réseau** : un échec
ne change pas la cible, la bascule remplace adresse, nom et machine ensemble, un choix efface
l'avis, oublier vide tout d'un coup, écrire une adresse inconnue n'invente ni nom ni machine.

**LE TEST A ATTRAPÉ UNE FAUTE PENDANT LE REMANIEMENT** : un ancien `choisir()` subsistait
avant le calcul de l'avis, si bien que l'avis était calculé sur la NOUVELLE cible — il
annonçait « ne répond pas » pour une machine qui était simplement hors ligne. Sans le test de
la transition, ce texte faux partait en production.

#### La page d'un serveur, et ce qu'elle retire du panneau latéral

**Toucher une icône de machine ouvre SA page** dans la colonne de droite : son état, son
adresse, son action, **le jeton d'appareil**, et — quand la machine
ne publie rien — le diagnostic complet avec les commandes à recopier. Le panneau latéral
garde ce qui se lit d'un coup d'œil : la pastille, la légende, le nom.

POURQUOI CE DÉPLACEMENT. Le panneau latéral portait l'état des machines **et** le
diagnostic entier, jusqu'aux commandes destinées à l'autre Mac. Le message le plus long
prenait la place des sessions, et il fallait faire défiler pour voir son propre travail.
Le diagnostic appartient à la MACHINE : il vit donc sur sa page.

##### Tailscale a quitté le panneau latéral, et ce qui restait a été rétabli

La colonne s'ouvrait sur une **carte d'état de Tailscale** — « connecté », « installé »,
« pas installé » — avec son action. Constat du propriétaire : « la partie Tailscale n'est
plus utile car intégrée dans le détail de la page serveur ». C'est exact, et c'est la
conséquence directe du déplacement précédent : l'état de CET APPAREIL est la **première
étape du parcours de chaque machine**, mesurée deux fois plutôt qu'une (`getifaddrs`,
plage `100.64.0.0/10`), et l'action — « Ouvrir Tailscale », « Installer Tailscale » — y est
rendue au même endroit, **au moment où une machine ne répond pas**. La carte, elle,
occupait le haut de la colonne en permanence, y compris quand tout allait bien.

**CE QUI A FAILLI SE PERDRE, ET QUI ÉTAIT DÉJÀ CASSÉ.** Sur un appareil neuf, la carte
portait l'unique bouton « Installer Tailscale ». Or la page qui donne les quatre étapes
n'était atteignable que par la vignette « Ajouter » du carrousel… **qui ne s'affiche pas
quand la liste est vide** : l'appareil qui a le plus besoin des quatre étapes — celui qui
n'a rien — n'y avait aucun accès. Le trou existait avant le retrait ; il serait devenu
visible après. La liste vide offre donc maintenant **« Ajouter un serveur »**, en premier,
au-dessus de « Saisir une adresse ».

Le type `EtatTailscale` (absent / installé / connecté) est parti avec la carte, son seul
lecteur, et `relireEtatTailscale()` ne fait plus que les **deux constatations** dont le
parcours a besoin : l'application est-elle là, et cet appareil est-il sur le tailnet.
L'état « installé mais aucun serveur en ligne » ne décrivait d'ailleurs pas Tailscale : il
décrivait la liste des Macs, que le panneau montre déjà (« 1 joignable », la légende de
chaque vignette).

Vérifié par capture : macOS sans le bloc (la colonne commence aux serveurs) et **iPhone
neuf** — conteneur vidé, application réinstallée — qui affiche la liste vide avec
« Ajouter un serveur ».

**« ESPACES DE TRAVAIL », ET NON « WORKSPACES ».** Le titre avait été recopié de
l'interface web pour que les deux se répondent ; le propriétaire a tranché : « et en
français, Workspaces = Espaces de travail ». La RÈGLE #1 du dépôt le demandait déjà, et
« Workspaces » se lisait comme un terme du protocole alors qu'il ne nomme qu'un dossier de
travail. Le protocole, lui, garde ses noms : `/v1/espaces` était déjà français, et
`workspaceRegistry` reste l'API du harness.

##### La page est structurée en quatre bandes, et rien ne s'y répète

Constat du propriétaire : « la page détail des serveurs est moche, tu peux faire quelque
chose ? À commencer par mieux structurer. » Le constat était juste, et la cause était
**structurelle**, pas esthétique : six blocs de même poids s'empilaient dans l'ordre où le
code avait grandi — en-tête, adresse, jeton, interrupteurs, bandeau d'erreur, diagnostic —,
si bien que le DIAGNOSTIC, raison d'être de la page, se lisait en dernier : sur un iPhone,
il fallait faire défiler le jeton d'un hôte et deux réglages pour savoir ce qui n'allait
pas. Le même fait y était dit quatre fois (« hors ligne » sous le titre, dans le bandeau
rouge, dans le résumé du parcours, et par le titre de l'étape 2), et deux avertissements de
jeton passaient avant toute information sur la machine — dont un **faux**, puisque l'état
« hors ligne » était pris pour un jeton refusé (voir `.jetonInvalide`).

L'ordre suit maintenant les questions qu'on se pose, et rien d'autre :

| Bande | Contenu | Ce qu'elle règle |
|---|---|---|
| 1. Identité | nom, **une** pastille d'état, adresse copiable, **une** action | l'état se dit une fois, et l'action proposée peut aboutir |
| 2. Diagnostic | la conclusion, puis les quatre constats | la démonstration, avec **une seule** méthode dépliée : celle de l'étape qui bloque |
| 3. Réglages de cette machine | jeton, suivi, filtre — **repliés** | chaque réglage reste à l'endroit qui le rend vrai, sans s'interposer entre l'adresse et le verdict |
| 4. Détail technique | l'erreur brute — **repliée**, et seulement si rien ne l'explique | une phrase en français n'est pas un détail technique |

**UNE SEULE PASTILLE, ET UN SEUL VOCABULAIRE.** La page disait l'état de la machine à
quatre endroits, et avec d'autres mots que le panneau latéral — « hors ligne sur le
tailnet » d'un côté, « hors ligne » de l'autre ; « en ligne · pas de DSH » ici, « pas de
DSH » là. Les mots vivent maintenant dans `EtatMachine`, que les deux endroits emploient :
la vignette ABRÈGE (« DSH · hôte ») parce qu'elle tient en 68 points, la page dit la phrase
entière (« DSH · hôte interrogé »), mais ce sont **les mêmes mots** — et 2 tests
l'éprouvent. La conclusion du diagnostic est calculée là aussi (`EtatMachine.conclusion`) :
elle décidait de trois choses à la fois — texte, symbole, gravité —, et une fonction pure
se teste, une vue non.

**L'ACTION PRINCIPALE CHANGE AVEC L'ÉTAT.** « Se connecter » était offert à toutes les
machines, y compris celles dont on sait déjà qu'elles ne répondront pas : le garde-fou
local évitait la requête, mais le seul résultat possible restait un message disant que la
machine est éteinte. La page propose donc « Choisir <un autre Mac> » quand la machine est
hors ligne et qu'une autre répond — sinon « Rafraîchir la liste » —, « Se connecter » ou
« Reconnecter » quand DSH y répond, « Revérifier » quand il reste à savoir. **Le bouton
« Tester » a disparu** : il testait l'adresse VISÉE par le modèle, pas celle de la page
ouverte — proposé sur la page d'une autre machine, il aurait testé la mauvaise, et un
bouton qui agit ailleurs est pire qu'un bouton absent.

**LE BLOC TECHNIQUE N'EST PLUS UN PAVÉ.** Il affichait en rouge, avec un triangle
d'alerte, une phrase en français — `messageHorsLigne` — que le garde-fou local range dans
le même champ que les erreurs : ce n'est pas un détail technique, et c'était la troisième
fois que la page disait la même chose. Il est maintenant replié, et il ne contient que les
erreurs que **rien n'explique** — celles-là seules valent un bloc à part.

Vérifié par capture macOS (`--page-seule`), sur les trois états qui comptent :

| État | Ce que la capture montre |
|---|---|
| **prêt** (MacBook Air, hôte interrogé) | pastille verte « DSH · hôte interrogé », « Reconnecter », « Ce serveur est prêt. », quatre constats verts — **la page entière tient sans défiler** |
| **pas de DSH** (MacMini) | pastille orange « pas de DSH », « Il reste une étape : « Le plugin `dsh-remote` est installé » », étapes 1-3 vertes, étape 4 avec la démarche d'installation dépliée |
| **hors ligne** (MacBook Pro de Camille) | pastille « hors ligne », action « Choisir MacBook », « Rien ne peut être joint sur cette machine… », étape 2 avec `tailscale status` / `tailscale up` — et l'explication « Il est hors ligne sur le tailnet : la découverte ne le propose donc pas » |

**PAS DE CAPTURE IPHONE CETTE FOIS**, et c'est un manque assumé : sur un simulateur
neuf, `--page-seule` n'a **pas de serveur courant** à montrer, et cet environnement
n'injecte pas l'appui qui ouvrirait la page. L'ancre a donc reçu la sonde qu'elle
n'exécutait pas (voir plus bas), mais pas la liste des machines, qui vient de l'hôte.

**L'ANCRE `--page-seule` LANCE DÉSORMAIS LA SONDE.** Le panneau latéral est ce qui la
lançait ; sans lui, les étapes 3 et 4 restaient à « vérification… », et **les deux états
qui comptent le plus — port fermé, plugin absent — n'étaient pas capturables** : la
capture de MacMini montrait « vérification… » au lieu de « pas de DSH ». Constaté en
essayant de capturer la page refaite.

**L'appui OUVRE la page ET se connecte.** Un geste, deux effets, et c'est délibéré : on
touche une machine pour s'y connecter, et la page est ce qui EXPLIQUE le résultat — état,
adresse, jeton, remèdes. J'avais un temps séparé les deux (l'appui ouvrait, un bouton
connectait) ; le propriétaire a tranché : « je voulais lancer une méthode ». Ce qui a changé
par rapport au début n'est donc pas le geste, mais l'ENDROIT du diagnostic : il s'affichait
dans la colonne de gauche, au milieu des sessions ; il vit maintenant sur la page de la
machine concernée.

**Deux mécanismes, parce que les plateformes diffèrent.** Sur macOS, les deux colonnes sont
visibles : la page remplace le contenu de droite. Sur iPhone, il n'y a pas de colonne de
détail : la page s'EMPILE (`NavigationLink` + `navigationDestination`), sinon l'appui ne
montrerait rien — un appui qui ne montre rien est un appui cassé.

Un échec de connexion au lancement force aussi la page : sans cela, le diagnostic ayant
quitté le panneau latéral, il ne se serait affiché NULLE PART.

##### Un seul signal de sélection sur la vignette

La coche du coin haut-gauche dit « c'est le serveur connecté », et depuis que l'appui
CONNECTE, c'est aussi celui dont la page est ouverte : les deux états coïncident toujours.

J'avais ajouté un **anneau bleu** autour de la vignette lue pour distinguer « connecté » de
« page ouverte ». Le propriétaire l'a fait retirer : un signal qui ne dit jamais rien de plus
qu'un autre est du bruit. La vignette garde donc trois indications seulement — la **coche**
(connecté), la **pastille** (la machine répond), la **légende** et l'**atténuation** (DSH
présent ou non).

##### Où va quoi : chaque réglage à l'endroit qui le rend vrai

Le partage a été fait **par nature**, pas par commodité :

| Réglage | Où | Pourquoi |
|---|---|---|
| État, adresse, actions, diagnostic, remèdes | **page du serveur** | cela ne vaut que pour UNE machine |
| **Jeton d'appareil** | **page du serveur** | mesuré : il est tiré par chaque hôte, celui d'un Mac ne vaut pas pour un autre |
| « Chargées en mémoire seulement », « Suivre l'activité » | **page du serveur** | ils portent sur la CONNEXION à une machine : l'un décide si l'on interroge CE serveur, l'autre filtre SA liste |
| Saisie manuelle d'une adresse | **feuille « Adresse »** | on vise une machine, on ne règle pas l'application ; elle s'ouvre depuis « Saisir une adresse » |

Les **Réglages** ne contiennent donc plus RIEN pour l'instant, et ils le disent : une
feuille vide sans explication ressemblerait à un écran cassé. `--adresse` est l'ancre de
vérification de la feuille d'adresse.

##### Les deux interrupteurs sont PAR SERVEUR — et je m'étais trompé

J'avais classé « Chargées en mémoire seulement » et « Suivre l'activité » comme des
préférences **générales**, au motif que le modèle n'en tenait qu'un seul drapeau. Le
propriétaire a demandé : « normalement, c'est spécifique à chaque serveur, non ? » — et il a
raison. Que le code soit global n'est pas un argument pour qu'il le reste :

- **suivre l'activité** décide si l'on interroge **ce** serveur toutes les trois secondes ;
- **chargées en mémoire seulement** décide ce qu'on affiche de **sa** liste.

Globaux, ils faisaient hériter chaque machine des choix faits pour la précédente : on
coupait le suivi pour un Mac endormi, et la machine suivante ne se rafraîchissait plus sans
qu'on sache pourquoi. Ils sont donc stockés **par serveur**, la clé étant l'**adresse
normalisée** — une machine nommée, saisie à la main ou atteinte par son adresse de tailnet
est la même. Le réglage d'une machine non connectée est enregistré et s'appliquera à la
connexion, ce que la page dit en toutes lettres.

3 tests couvrent l'indépendance des machines, l'unicité de la clé sous trois écritures
d'adresse, et la relecture après relance.

`--page-seule` est une **ancre de vérification** : elle remplace la fenêtre par la page du
serveur courant, ce qui permet de la capturer sur iPhone, où elle ne s'obtient autrement
qu'en appuyant sur une icône — un appui que cet environnement ne sait pas injecter.

#### « Serveur DeepSeek Harness », et un compte qui ne promet que ce qui marche

La section s'appelait **« Serveurs »**, avec un compte « **N en ligne** ». Deux imprécisions,
corrigées à la demande du propriétaire :

- le titre ne disait pas **de quel genre de serveur** il s'agit — or cette liste ne contient
  que des machines capables d'héberger DSH ;
- le compte annonçait des machines **allumées**, alors qu'une machine en ligne dont DSH ne
  répond pas n'est **pas un serveur utilisable** : l'annoncer la faisait passer pour tel.

Elle s'appelle donc **« Serveur DeepSeek Harness »**, et le compte de droite est celui des
machines **en ligne ET dont DSH répond** (« 1 joignable »). Deux garde-fous :

- **tant que la sonde n'a pas rendu son verdict**, le compte affiche « vérification… » et non
  « 0 » : on ne sait pas encore, et compter faux serait pire que ne pas compter ;
- **la liste continue de montrer TOUTES les machines**, avec leurs états — c'est ce qui
  permet de comprendre pourquoi une machine ne compte pas (hors ligne, ou DSH absent).

Vérifié par capture : trois vignettes affichées (« DSH · hôte », « pas de DSH », « hors
ligne ») et « 1 joignable » à droite.

#### Une sonde annulée n'est pas un verdict

**Faux négatif mesuré, et corrigé.** La sonde est relancée à chaque changement de liste, et
SwiftUI **annule** la précédente. Or une requête annulée lève : le `catch` la rangeait en
« pas de DSH », et le groupe rendait donc un verdict VIDE — qui écrasait le bon. Le journal
de l'application montrait la suite exacte :

```
[sonde] debut : 2 candidat(s), jeton 43 caracteres
[sonde] fin : 1 serveur(s) DSH sur 2      ← le bon verdict
[sonde] fin : 0 serveur(s) DSH sur 2      ← une sonde annulée l'écrase
```

Aucune machine n'avait changé d'état : la seule différence était l'annulation. Le verdict
n'est donc publié que si la sonde est allée au bout (`guard !Task.isCancelled`). Après
correction, la page affiche « en ligne · DSH · hôte interrogé », vérifié par capture.

#### Une bascule de serveur doit se PROUVER

Trouvé sur la même capture, et corrigé : l'application annonçait

> « http://127.0.0.1:58674 **ne répond pas** : basculé sur « MacBook Air de Camille » »

alors qu'elle était **connectée** à cette adresse, qui répondait. `ajusterAuParc` se
déclenchait dès que l'adresse courante n'était pas une machine **découverte et en
ligne** — sans qu'aucune requête ait échoué. Une adresse saisie à la main, une adresse de
configuration, une instance locale : toutes étaient déclarées mortes par simple
ignorance.

La règle est désormais : **pas de preuve, pas de bascule**. L'échec est consigné là où il
est constaté — au refus motivé de `connecter()` (machine hors ligne) ou à l'échec d'une
tentative réelle — et il est effacé dès qu'une connexion réussit. L'avis dit alors ce qui
a été constaté, et rien de plus : « est hors ligne sur le tailnet » n'est pas « ne répond
pas ». 7 tests couvrent la décision, qui est une fonction pure.

**ET UN CAS NE BASCULE PAS DU TOUT** : la machine qui **répond** mais dont le port 80 est
vide (`-1004`). C'est la seule situation où l'application sait exactement quoi faire dire
et faire faire — et basculer remplaçait ce message par un avis de bascule, effaçant
l'information utile *et* la machine que l'utilisateur venait de choisir. Ce cas garde donc
sa place, avec ses commandes.

#### Les commandes à taper ailleurs se COPIENT

Le message du Mac qui ne publie rien affichait ses commandes en texte monospace, noyées
dans un paragraphe : il fallait les sélectionner à la main, sur un téléphone, au milieu
d'un texte. Elles sont maintenant dans des encadrés, **chacune avec son bouton de copie**
(`LigneCommande`) — parce que ces commandes ne sont pas faites pour être lues ici, mais
tapées sur l'autre Mac.

**LA COMMANDE ÉTAIT FAUSSE, ET ELLE EST MAINTENANT VÉRIFIÉE.** L'ancienne —
`tailscale serve --bg 80 http://127.0.0.1:3080` — ne pouvait pas fonctionner : `--bg` ne
prend pas de port, et `serve` n'accepte qu'une seule cible. La nouvelle a été passée sur
cette machine, et `tailscale serve status --json` est resté **identique avant et après** :
elle reproduit donc exactement la configuration qui marche.

```bash
tailscale serve --bg --http=80 http://127.0.0.1:3080   # publier DSH sur le port 80 du nom MagicDNS
tailscale serve status                                  # vérifier ce qui est publié
```

Dans ce cas précis, le pavé de transport (`NSURLErrorDomain -1004 … | sous-jacent …`)
n'est **plus affiché** : il redisait en rouge, et en charabia, ce que l'encadré dit en une
ligne et répare. Il reste affiché pour toutes les autres causes, où il est le seul
diagnostic — et il est de toute façon conservé dans `diagnostic.json`.

#### Les séparateurs de ligne, sur macOS

Le propriétaire a demandé s'ils étaient utiles sur le Mac : ils ne le sont pas. Une colonne
de navigation macOS n'en dessine aucun, et ici ils découpaient des lignes qui appartiennent
au **même** objet — un espace et ses sessions, une explication et sa commande. Ils sont
donc masqués sur macOS (`.sansSeparateurMac()`), et **conservés sur iOS**, où une liste
encartée les utilise pour séparer des réglages distincts.

**Non vérifié à l'écran, et dit comme tel** : `screencapture` exige l'autorisation
« Enregistrement de l'écran », refusée dans cet environnement. La modification emploie
l'API de ligne documentée (`listRowSeparator`), appliquée à chaque ligne et non au
conteneur — posée sur un conteneur, elle serait sans effet, ce qui est pire qu'un
séparateur.

### Installer sur l'iPhone : ce qui bloque, mesuré

Trois faits établis sur cette machine, dans cet ordre :

1. **Xcode accepte une destination iOS** pour ce paquet. `xcodebuild -showdestinations
   -scheme DSHRemote` liste `platform:iOS … Any iOS Device` (malgré l'avertissement
   « Supported platforms for the buildables in the current scheme is empty »).
2. **Le code compile et se lie pour un vrai iPhone** :
   `xcodebuild -scheme DSHRemote -destination 'generic/platform=iOS' build` →
   `BUILD SUCCEEDED`, `-target arm64-apple-ios17.0`, SDK `iPhoneOS26.5`.
   C'est une vérification réelle de la chaîne de compilation iOS, pas une supposition.
3. **Mais Xcode ne produit PAS de `.app`** : un exécutable SwiftPM donne un **binaire
   Mach-O nu** (`Build/Products/Debug-iphoneos/DSHRemote`), sans bundle ni `Info.plist`.
   Or iOS n'installe que des paquets `.app` signés. **Ce paquet ne peut donc pas être
   installé sur l'iPhone tel quel**, quel que soit le réglage de signature.

**C'est fait** : `DSHRemote.xcodeproj` produit une vraie cible d'application
(`com.apple.product-type.application`) qui consomme `DSHRemoteKit`. Vérifié :
`xcodebuild -destination 'generic/platform=iOS Simulator' build` → `BUILD SUCCEEDED`,
et le produit contient bien `DSHRemote.app` avec son `Info.plist` et son
`CFBundleIdentifier`.

### Restructuration imposée par cette contrainte

Une cible d'application **ne peut pas lier un exécutable**. L'interface SwiftUI a donc
dû quitter la cible exécutable `DSHRemoteApp` pour rejoindre la bibliothèque
`DSHRemoteKit`, qui porte désormais tout le code réutilisable. Conséquence : le projet
Xcode ne produit qu'une application **iOS**.

**MISE À JOUR, après une confusion coûteuse.** Ce paragraphe a d'abord conclu que
« l'application se lance depuis le projet Xcode, qui couvre iOS **et** macOS ». C'était
faux — `SDKROOT = iphoneos` — et la suite est instructive : privé de lancement macOS, on
en vient à exécuter le binaire du simulateur comme un programme du Mac, où dyld le
refuse (`DYLD_ROOT_PATH not set for simulator program`). Le paquet livre donc de nouveau
une application macOS (`Sources/DSHRemoteApp`, `swift run DSHRemoteMac`), qui n'ouvre que
`VuePrincipale` : la même vue que sur iPhone.

### Installé sur l'iPhone — et l'adresse qui marche vraiment

**C'est fait.** Xcode a enregistré l'appareil, créé le profil de provisionnement, et
l'application est **installée et signée** par l'équipe de développement du propriétaire
(son identifiant n'est **pas** reproduit ici : c'est un identifiant de compte, et
`scripts/check-secrets.sh` le refuse — à juste titre, il était cité jusqu'ici) :

```bash
xcodebuild -project DSHRemote.xcodeproj -scheme DSHRemote \
  -destination 'id=<iphone>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <iphone> <chemin>/DSHRemote.app
```

**Correction importante sur l'adresse.** `tailscale serve` publie l'instance sur le
**port 80 du nom MagicDNS**, PAS sur `100.x.y.z:3080` — le harness n'écoute que sur la
boucle locale, et rien ne répond sur l'IP tailnet avec un port. Mesuré :

| Adresse | Résultat |
|---|---|
| `http://100.101.102.103:3080` | `000` — rien n'écoute |
| `http://<nom-magicdns-du-mac>` (port 80) | `200` — le bon chemin |

Conséquence : l'adresse à saisir dans l'application est le **nom MagicDNS**, sans port.
Obtenir le nom exact : `tailscale serve status`.
C'est un nom de domaine qualifié, donc App Transport Security s'y applique et le HTTP en
clair y est bloqué — d'où une exception `NSExceptionDomains` **ciblée sur ce seul
domaine** dans `App/Info.plist`, et non `NSAllowsArbitraryLoads` quiouvrirait le clair
vers n'importe quel hôte.

**L'exception ATS est injectée dans le paquet construit, pas dans les sources.**

Le HTTP en clair vers un nom de domaine exige une exception, et celle-ci impose d'écrire
le nom du tailnet — ce que la RÈGLE #0 interdit dans le dépôt. J'ai d'abord tenté
`$(DSH_ATS_DOMAINE)` depuis un xcconfig : **mesuré, cela ne marche pas**, Xcode n'étend
pas les variables de build dans les **clés** d'un plist (clé littérale : intacte ; clé
variable : reste littérale).

La phase de build « Exception ATS » (`Scripts/injecter-exception-ats.sh`) résout le
problème autrement : elle modifie le `.app` **construit**, jamais les sources. Le domaine
vient de `Config/DomaineTailnet`, fichier local ignoré par git :

```bash
printf 'mon-tailnet.ts.net\n' > Config/DomaineTailnet
```

**LE FICHIER PORTE LE DOMAINE DU TALNET, PAS LE NOM D'UNE MACHINE — défaut vu à
l'écran, puis corrigé.** Une première version y mettait le nom MagicDNS du Mac. L'exception
était alors *présente dans le plist* et **inopérante pour tous les autres Macs** :
`macmini.mon-tailnet.ts.net` est un **frère**, pas un sous-domaine, donc App Transport
Security le refusait en `-1022` — « ATS refuse le clair vers cet hôte » — alors que la
fiche du Mac lui-même fonctionnait. Le remède est le suffixe commun à toutes les machines,
déclaré avec `NSIncludesSubdomains`.

Mesuré, en **boîtier applicatif** (bundle) et vers un autre Mac du tailnet :

| Exception déclarée | Résultat |
|---|---|
| `mon-mac.mon-tailnet.ts.net` (nom de machine) | **`-1022`** — ATS refuse : l'exception ne couvre pas les voisins |
| `mon-tailnet.ts.net` + `NSIncludesSubdomains` | `-1004` — la requête part réellement ; ce Mac-là ne servait simplement pas DSH |

`NSIncludesSubdomains` est donc indispensable **dans les deux chemins d'empaquetage**
(phase Xcode pour iOS, `Scripts/empaqueter-app-macos.sh` pour le Mac). Sans lui,
l'exception ne couvre que le domaine nu et ne protège aucune machine.

Le script valide la forme du domaine, et **ne fait pas échouer le build** si le fichier
est absent : sans exception, l'application se construit et se lance, seule la connexion
HTTP vers un nom de domaine est refusée. Le domaine n'est jamais écrit dans un journal de
build : seul son nombre d'étiquettes l'est, de quoi vérifier qu'il est complet.

Deux pièges rencontrés, notés pour la suite :

- le bac à sable des scripts de build (`ENABLE_USER_SCRIPT_SANDBOXING`) empêchait le
  script de s'exécuter — désactivé pour cette cible ;
- **un build incrémental ne relance pas la phase** : le plist restait celui d'avant, ce
  qui a masqué le résultat. Vérifier après un `clean build`.

**Solution alternative, sans aucune exception** : publier en HTTPS, que Tailscale signe
d'un vrai certificat — `tailscale serve --https 443 http://127.0.0.1:3080` — puis viser
`https://<nom-magicdns>/`. Dans ce cas, retirer la phase « Exception ATS » du projet.

### Pour installer sur l'iPhone : une action manuelle, inévitable

Construire pour l'appareil échoue aujourd'hui sur deux points **administratifs**, pas
techniques :

```text
error: Device "Mon iPhone" isn't registered in your developer account.
error: No profiles for 'org.example.DSHRemote' were found.
```

L'enregistrement de l'appareil et la création du profil exigent la session Apple ID
ouverte dans Xcode. `xcodebuild -allowProvisioningUpdates` ne suffit pas : il lui
faudrait une clé d'API App Store Connect ou un mot de passe d'application — un secret
que ce dépôt ne manipule pas.

Marche à suivre, une seule fois :

1. Ouvrir `DSHRemote.xcodeproj` dans Xcode.
2. Cible `DSHRemote` ▸ onglet **Signing & Capabilities** ▸ cocher
   **Automatically manage signing** et choisir l'équipe.
3. Brancher l'iPhone, le choisir comme destination, puis **Run**. Xcode enregistre
   l'appareil et crée le profil lui-même.
4. Sur l'iPhone, si iOS le demande : **Réglages ▸ Général ▸ VPN et gestion de
   l'appareil**, faire confiance au profil de développeur.

### Serveur mémorisé, et icône selon le type de machine

**L'adresse est mémorisée** entre deux lancements (`UserDefaults`), avec le nom
lisible du serveur. Ressaisir 40 caractères à chaque ouverture est la friction
qui fait abandonner une application. Un bouton **✕** permet d'oublier le serveur
— sans quoi une adresse enregistrée par erreur ne se retirerait qu'en
désinstallant.

**Le jeton, lui, n'est PAS mémorisé là** : il vit au trousseau, qui est fait pour
cela. `UserDefaults` est un fichier de préférences lisible par une sauvegarde, ce
qui n'est pas un endroit pour un secret.

**L'icône suit le type de machine** : `macbook`, `macmini`, `macstudio`,
`desktopcomputer` en repli. Elle apparaît à côté de l'adresse et dans l'en-tête du
journal, et à côté de chaque machine de la liste des serveurs.

**DÉFAUT RÉEL, TROUVÉ PAR UNE CAPTURE D'ÉCRAN, PUIS CORRIGÉ.** Une première version
employait `macbook.air` et `macbook.pro` — qui **ne sont pas des symboles SF** — et
`imac`, qui n'en est pas un non plus. `Image(systemName:)` ne signale rien dans ce
cas : il n'affiche **rien**. Résultat : les deux Macs les plus courants (Air et Pro)
apparaissaient sans icône, et le repli générique n'était jamais atteint puisqu'un nom
était bien rendu. Les lignes d'un MacBook Air et d'un MacBook Pro sont restées vides à
l'écran jusqu'à ce que la capture du simulateur le montre. Trois conséquences :

- seuls des symboles qui existent sont employés (`macbook` pour tout portable) ;
- un test interroge le **catalogue de la plateforme** (`NSImage(systemSymbolName:)`)
  pour chaque nom que la déduction peut produire — un test qui compare des chaînes ne
  peut pas voir ce défaut, puisqu'il vérifiait la valeur attendue… qui n'existait pas ;
- SF Symbols ne distingue pas un Air d'un Pro : l'icône dit « portable » ou « bureau »,
  ce que la donnée porte réellement.

**LIMITE ASSUMÉE.** Tailscale ne rapporte pas le modèle matériel :
`tailscale status --json` donne le système d'exploitation, pas le châssis.
L'icône se déduit donc du NOM, que macOS construit à partir du modèle — et la
détection gère les deux formes, le nom (« MacBook Air de … ») comme le nom
d'hôte Tailscale, qui remplace les espaces par des tirets
(`macbook-air-de-…`, `macmini`). Sans ce repli, une adresse saisie à la main
afficherait l'icône générique pour un portable. Une machine renommée « bureau »
retombe sur l'icône générique, ce qui reste correct.

### Le suivi de l'activité

La liste se rafraîchit **toutes les 3 secondes** tant qu'un serveur est joignable,
et l'interrupteur « Suivre l'activité » permet de l'arrêter.

Sans ce suivi, les pastilles ne changeaient qu'au lancement ou par glissement :
le propriétaire a vu « des points bleus partout » alors que le serveur signalait
déjà deux sessions en cours. **Un indicateur d'activité qui ne s'actualise pas
est pire qu'aucun indicateur** : il donne une image fausse avec l'autorité d'une
mesure.

### Interroger ne suffisait pas : la liste ne se redessinait pas

Le suivi ci-dessus interrogeait bel et bien le serveur — et l'écran restait faux.
Mesuré : le serveur annonçait la session **au repos** avec **30 enregistrements**,
et l'écran affichait toujours les carrés orange et « 27 évts », **une minute plus
tard**. Les 54 interrogations tracées côté hôte ne servaient donc à rien de
visible.

La cause est une propriété de `SessionListee` qui est nécessaire ailleurs :
son égalité est une égalité d'**identité** (projet + identifiant). Sans elle, la
sélection d'une session se perdrait à chaque rafraîchissement de 3 secondes —
le journal grandit, donc la valeur change, donc la session sélectionnée
paraîtrait « autre ». Mais SwiftUI se sert de `==` pour décider de **redessiner**
une vue : une ligne dont seul le statut changeait était considérée comme
inchangée et n'était jamais redessinée. Le défaut ne se voyait que lorsque la
liste changeait d'ordre — c'est-à-dire presque jamais.

La ligne reçoit désormais des valeurs simples (`AfficheLigneSession`), dont
l'égalité est **synthétisée** : l'identité reste au modèle, la comparaison
d'affichage reste à la vue. C'est la correction qui rend le suivi visible, et
sans elle la pastille verte n'aurait jamais pu apparaître.

Le rafraîchissement est fréquent parce qu'il est bon marché : la liste ne relit
pas les journaux, elle relit un résumé mis en cache côté serveur et interroge
l'état des agents. Il ne touche pas non plus au journal ouvert, pour ne pas
déplacer la lecture sous les yeux de l'utilisateur, et un échec passager ne
signale rien — l'utilisateur n'a rien demandé, il ne doit pas être interrompu.

### Quatre états affichés, et un cinquième qui ne s'affiche pas

| Affichage | Sens |
|---|---|
| carrés orange qui tournent | `en_cours` — un tour s'exécute |
| **point orange plein** | `attendReponse` — l'agent attend une **décision de l'utilisateur** |
| **point vert** | un tour vient de **finir sans être vu** (voir ci-dessous) |
| anneau vide | état **inconnu** — la session n'est pas ouverte dans le processus |
| *(rien)* | `inactif` — chargée dans le harness, au repos |

**La session au repos n'affiche RIEN**, et c'est délibéré : c'est l'état le plus
fréquent, et une pastille permanente pour lui apprend à ne plus regarder les
pastilles — précisément quand l'une change. Une version précédente affichait un point
bleu ; il a été retiré, et l'interface web masque elle aussi sa pastille dans ce cas.
L'emplacement reste occupé, donc les titres restent alignés.

**Le point orange n'est pas l'animation orange** : les carrés veulent dire « ça
travaille », le point plein veut dire « **ça t'attend** ». Une session dans cet état ne
repartira pas toute seule, et c'est la seule information de la liste qui demande une
action immédiate. L'ordre de priorité le dit : décision attendue > travail en cours >
rappel de fin > silence.

L'anneau vide mérite une explication : dans une première version, l'état inconnu
s'affichait comme un point **vert**, donc comme une session terminée. L'interface
affirmait ainsi une conclusion que le serveur n'avait pas donnée — et sur une
installation où le harness n'avait pas encore rechargé le plugin, TOUTES les
sessions apparaissaient vertes, ce qui a été signalé comme un défaut. Un état
inconnu se montre comme inconnu.

### La pastille verte : un rappel de fin, pas un état

Le vert ne dit **pas** « terminée » — le repos ne dit plus rien du tout. Il dit :
*cette session a fini de travailler pendant que tu ne la regardais pas*. C'est le
rappel de fin de l'interface web, et sa règle a été recopiée de son implémentation
(`syncCompletedNotifications` du contrôleur de sessions) plutôt que devinée :

1. à la **première** observation d'une session, on retient seulement si elle
   travaille — une session déjà au repos à l'ouverture de l'application ne
   produit aucun rappel, sinon la liste s'ouvrirait couverte de points verts ;
2. la transition **travail → repos** arme le rappel, sauf pour la session que
   l'utilisateur regarde ;
3. repasser en travail **désarme** le rappel ;
4. une session qui quitte la liste (filtre, suppression) perd son rappel ;
5. **ouvrir** la session efface son rappel : c'est la définition de « vu ».

La règle vit dans `RappelsDeFin`, isolée du modèle et testée sur ses transitions
— première observation, session regardée, retour en travail, disparition. Ce sont
les cas qu'une vérification à l'œil ne couvre pas.

**LIMITE ASSUMÉE, la même que celle du web** : ce rappel est en mémoire. Il
n'observe que ce que l'application voit — une fin de tour survenue pendant que
l'application était fermée ne produit pas de pastille verte. L'interface web a
exactement la même limite, son état de rappel étant lui aussi en mémoire.

### « L'agent attend une réponse » : signalé, pas résolu

Le point orange vient d'un champ que l'hôte publie par session
(`attendReponse`), alimenté par l'observation des deux waterfalls du harness
(question d'un tool, autorisation). Sa mécanique — et le piège qui a coûté trois
mesures — est racontée dans le [README du
plugin](../../plugins/dsh-remote/#lagent-attend-une-reponse--observer-sans-repondre).

**CE QUE L'APPLICATION FAIT, ET CE QU'ELLE NE FAIT PAS.** Elle **signale** qu'une
décision est attendue ; elle ne permet **pas** d'y répondre. Répondre exigerait de
retirer à l'interface web son rôle de répondeur terminal — ce n'est pas un ajout
anodin, et l'annoncer sans le faire serait pire que de l'ignorer. Le champ est donc
lu, jamais écrit.

Un hôte plus ancien ne renvoie pas `attendReponse` : `nil` signifie « ne sait
pas », et l'application s'abstient — elle n'affiche pas un point orange qu'elle
devrait deviner.

### « Chargée » n'est pas « active »

Le filtre de la liste s'appelle **« Chargées en mémoire seulement »**, et non
« vivantes » : il retient les sessions que le harness garde dans son processus —
donc reprenables instantanément — sans rien dire de leur activité.

La distinction n'est pas cosmétique. Sur une installation réelle, dix sessions
étaient chargées, dont sept dont le dernier évènement datait de la minute du
démarrage du harness : comportement normal après une journée de travail, mais
l'étiquette « vivantes » le faisait passer pour une anomalie. L'activité réelle
se lit dans `statut` (`en_cours` / `inactif`), qui vaut `null` — état inconnu —
quand la session n'est pas ouverte dans le processus.

### Arbre des sessions, groupé par espace de travail

L'application reproduit l'arbre de l'interface web plutôt que d'inventer une
présentation différente pour le même contenu : un dossier par espace de travail,
ses sessions dessous, les sous-agents en retrait et marqués, et l'âge de chaque
session (« 1min », « 6h », « 3j »).

Une liste plate de plus de cent sessions mêlant dix projets est illisible : on ne
cherche pas « une session », on cherche « la session de ce projet ».

Deux choix de données méritent d'être notés :

- **Le nom d'espace vient de `cwd`**, jamais du nom du dossier de projet. DSH
  encode les chemins en remplaçant les `/` par des `-`, ce qui rend
  `dsh-plugins` indiscernable de `dsh/plugins` ; un libellé déduit d'un encodage
  perdant ne doit pas primer sur une valeur exacte. *(Repli seulement : quand l'hôte
  publie ses espaces, c'est son titre qui s'affiche — voir ci-dessous.)*
- **Le rattachement d'un sous-agent est INDICATIF.** L'en-tête d'un sous-agent ne
  nomme pas sa session parente : on les place sous l'espace de leur parent, sans
  prétendre à une exactitude que la donnée ne porte pas.

#### Les deux tris ne suivent pas la même date

Règle de l'interface web, **lue dans le service hôte** (`dsh-workspace`), et non déduite
d'une capture :

| Élément | Date qui classe | Sens |
|---|---|---|
| **Espaces** | la **création** de leur session la plus récente (`newestAt`), ou du dossier pour un espace vide | plus récent en haut |
| **Sessions** | leur **dernière activité** | plus récente en haut |

L'application triait les espaces par **activité** : l'arbre remontait à chaque message
reçu, et déplaçait sous le doigt l'élément qu'on visait. Deux espaces de même date sont
départagés par leur chemin, comme le fait le service hôte — sans quoi l'ordre
s'inverserait d'un rafraîchissement à l'autre.

La **lignée n'entre pas dans l'ordre** : un sous-agent se classe par son activité, et
c'est le rendu qui l'indente. C'est aussi le choix du web (« build one group without
projecting session lineage into presentation »).

#### Les espaces viennent du registre de l'hôte, vides compris

`GET /v1/espaces` (plugin) publie le registre : identifiant, titre, chemin, création, et
**la liste des sessions rattachées**. L'application l'utilise quand `capacites.espaces`
vaut `true`, et retombe sinon sur son regroupement par `cwd`.

- **Un espace sans session s'affiche**, avec une icône distincte : `tray` (plateau vide)
  et la mention « aucune session », au lieu du dossier. Il n'est **pas** rendu comme un
  groupe dépliable — un chevron qui ne révèle rien est un mensonge d'interface. SF
  Symbols n'a pas de « dossier ouvert », contrairement aux icônes du web
  (`IconFolderOpen16` / `IconFolderClose16`) : le dossier reste donc identique, et
  l'état déplié se lit au chevron de la liste.
- **L'appartenance est un fait, plus une comparaison de chemins** : une session dont le
  `cwd` a changé reste dans son espace, et une session qu'aucun espace ne revendique va
  dans « Sans espace », en dernier — le « Ungrouped » du web.
- **« Vide » est un fait du registre**, pas de l'affichage : une recherche qui masque
  toutes les sessions d'un espace ne fait pas clignoter son icône.

### Le piège du jeton : deux secrets de 43 caractères

Le coffre contient **deux** secrets de 43 caractères en base64url :

| Clé | Rôle |
|---|---|
| `dsh-remote/device-token` → `payload.token` | **le** jeton d'appareil, celui qu'attend le plugin |
| `client-connection/browser-session` → `payload.secret` | secret qui signe les cookies du navigateur |

Les deux passent le contrôle de forme, et **seul le premier est accepté** : copier
le second produit un `401` indiscernable d'un jeton tronqué. Deux garde-fous en
découlent :

- la commande à employer cible **l'enregistrement**, pas une ligne « token » :

```bash
python3 -c "
import yaml, os
d = yaml.safe_load(open(os.path.expanduser('~/.dsh/.credentials.yaml'), encoding='utf-8'))
print(d['records']['dsh-remote/device-token']['payload']['token'])
"
```

- l'application affiche une **empreinte** de 8 caractères hexadécimaux du jeton
  qu'elle détient (`Documents/diagnostic.json`, champ `empreinteJeton`), jamais
  le jeton. Comparer cette empreinte à celle du coffre dit lequel est détenu,
  sans rien exposer.

### Adresse : deux pièges corrigés après essai sur l'appareil

**1. La valeur par défaut était trompeuse sur iPhone.** Le champ partait avec
`http://127.0.0.1:3080`, la bonne valeur sur le Mac — mais sur iOS, `127.0.0.1`
désigne **le téléphone lui-même**. La connexion échouait donc en `-1004`
(« rien n'écoute sur cet hôte et ce port »), ce qui envoie chercher une panne
réseau là où le problème est une valeur par défaut fausse. Le champ part
désormais **vide** sur iOS, avec un exemple en filigrane : aucune adresse n'y est
devinable, et une valeur fausse est pire qu'une absence de valeur.

La connexion automatique au lancement est également désactivée quand l'adresse
est vide : afficher un échec de transport avant toute action de l'utilisateur
accuse le réseau à tort.

**2. Le bouton « Rafraîchir » ne pouvait rien faire — il peut de nouveau.** La
découverte LOCALE est impossible sur iPhone, donc appuyer réassignait une liste vide :
ni succès, ni erreur, ni changement. Il n'était alors proposé que là où il changeait
quelque chose, et l'action utile — **« Tester l'adresse »** — avait été ajoutée : elle
vérifie l'adresse ET le jeton, puis annonce le résultat (nombre de sessions, ou la
raison exacte de l'échec). Un bouton sans effet est un mensonge d'interface.

Depuis que l'hôte publie la liste, le bouton a de nouveau un effet **dès qu'un serveur
est joint** : il redemande la liste à l'hôte. Le bouton est donc affiché sur iPhone
quand une connexion existe, et masqué avant — la règle n'a pas changé, c'est la
capacité qui a changé.

Ajoute aussi : la découverte part d'une tâche détachée, car la lancer depuis
l'initialisation du modèle exécutait un processus sur le fil principal et
pouvait retarder l'affichage de la fenêtre.

### Le jeton sur l'iPhone

La lecture automatique du coffre ne fonctionne **pas** dans le simulateur : son
conteneur est en bac à sable et ne voit pas le `~/.dsh` du Mac — vérifié, l'application
affiche « Aucun jeton d'appareil » alors que `DSH_REMOTE_COFFRE` désigne bien le fichier.
Sur un iPhone réel, ce chemin n'existe de toute façon pas : le jeton se saisit **une
fois** dans le champ prévu, puis il est conservé au trousseau.

**Prérequis côté appareil**, indépendants du code : brancher l'iPhone en USB (ou activer
la synchronisation Wi-Fi), l'appairer et faire confiance à cet ordinateur, puis activer
**Réglages ▸ Confidentialité et sécurité ▸ Mode développeur** sur l'iPhone. Tant que
`xcrun devicectl list devices` répond `No devices found`, aucune installation n'est
possible — c'est un préalable matériel, pas logiciel.

### Écriture : répondre à l'agent, et l'interrompre

L'application n'est plus seulement une surface d'observation : le journal ouvert
porte un **composeur** en bas de l'écran (champ, choix du mode, envoi) et un
bouton **Arrêter** quand un tour s'exécute.

Trois décisions d'interface, chacune née d'un défaut réel :

1. **Le texte n'est effacé qu'après l'acquittement de l'hôte.** Un échec de réseau
   ne doit pas coûter à l'utilisateur ce qu'il vient d'écrire.
2. **Rien ne s'affiche qui ne puisse agir.** Le composeur n'apparaît que si l'hôte
   annonce `capacites.ecriture`, et le bouton **Arrêter** que si la session tourne
   *et* que `capacites.annulation` est là. Un hôte plus ancien ne renvoie pas ce
   champ : l'application s'abstient au lieu de proposer un bouton mort.
3. **L'idempotence est portée par le client.** `EnvoiEnAttente` conserve
   l'identifiant d'envoi tant que l'hôte n'a pas acquitté : un appui rejoué après
   une coupure réseau **ne crée pas de second message**. Un texte différent, ou un
   envoi déjà acquitté, tire un identifiant neuf.

Le mode d'envoi est écrit en clair — **« À la suite »** ou **« Tout de suite
(interrompt) »** — plutôt que caché derrière une icône : la différence entre tenir
la file et s'insérer dans un tour en cours ne se devine pas.

L'annulation **conserve la file d'attente** : ce qui n'a pas encore été traité
reste en attente. Une session froide est refusée (`404`) — il n'y a rien à
interrompre.

### Un défaut trouvé en regardant, pas en compilant

L'écran de journal s'ouvrait sur un en-tête correct et **« Journal (0 affichés) »**
pour une session de 48 évènements. La cause n'était pas le protocole : `ouvrir()`
existait dans le modèle mais **n'était appelé par aucune vue** — la sélection
remplissait le détail sans jamais demander le journal. Compiler ne pouvait pas le
voir ; le simulateur, si, en une capture.

Le chargement tient désormais à un `.task(id: session.id)` dans la vue du journal,
et non à un effet de bord de la sélection : changer de session relit le journal,
et l'écran ne peut plus mentir sur son contenu.

### Ce qui reste non prouvé

- **Le PIXEL du point orange.** La décision est prouvée de bout en bout — la charge
  utile réelle de l'hôte donne `attendReponse: true` pour une session bloquée sur
  une question, et `EtatSession` rend `.attendReponse`, la valeur exacte que la
  pastille traduit en point orange. Mais la capture d'écran du point lui-même
  manque : elle demanderait une instance de test *dont l'hôte publie le champ*, et
  l'application vise désormais l'instance réelle par sa découverte — dont le plugin
  est antérieur au champ. **Conséquence pratique pour toi : tant que le harness
  n'est pas redémarré, le point orange ne peut pas apparaître** (le plugin chargé
  ne connaît pas `attendReponse`), exactement comme l'écriture.
- **Le clic sur « Envoyer » dans le simulateur iOS.** Le composeur est **observé**
  (capture), la frappe ne l'est pas : cet environnement n'injecte pas de texte dans
  le simulateur (ni frappe clavier vers l'appareil, ni « Coller » par appui long —
  les deux essayés et mesurés). Le chemin d'envoi est prouvé par ailleurs, à trois
  niveaux : `dsh-remote-ctl prompt`, l'essai d'intégration `ecritureReelle` contre
  un hôte réel, et les tests d'encodage/décodage des types d'écriture.
- **Le rendu de l'interface macOS.** `screencapture` exige l'autorisation
  « Enregistrement de l'écran ». L'application **compile et démarre sans planter**
  (processus vivant après 6 s, fenêtre 1100×720 présente), mais son rendu n'a pas été
  observé — alors que celui de la version iOS l'a été, par `simctl io screenshot`.
  Précision ajoutée après mesure : **le projet Xcode ne produit pas d'application
  macOS native** (`SDKROOT = iphoneos`, `SUPPORTED_PLATFORMS = "iphoneos
  iphonesimulator"`). Le rendu macOS n'est donc plus seulement non observé, il n'est
  plus produit par ce projet — la formulation précédente, « le projet couvre iOS et
  macOS », était trop large. Une destination « My Mac (Designed for iPad) » existe,
  mais la construction échoue faute de profil de provisionnement pour ce Mac.
- **Tout essai sur iPhone réel** : ~~voir le point 3 ci-dessus~~ **fait depuis** —
  l'application est installée et signée sur l'appareil du propriétaire, et la section
  « Installé sur l'iPhone » plus haut en donne les commandes et les mesures. Cette
  ligne est conservée barrée parce qu'elle a dit le contraire pendant plusieurs
  commits, alors que ce même fichier affirmait déjà l'installation : deux
  affirmations incompatibles dans un document dont l'argument EST le tableau des
  preuves, c'est précisément ce que la RÈGLE #5 interdit.
- **Les questions de l'agent et les approbations.** Le composeur envoie un message,
  il ne répond pas à un `ask_user` ni à une demande de permission : ces surfaces ne
  sont pas exposées par le plugin, pour la raison documentée dans son README.

---

## Pourquoi un tool en ligne de commande avant toute interface

`dsh-remote-ctl` existe pour **prouver** le transport sans interface graphique. Tant
qu'il n'affiche pas les bonnes données, écrire du SwiftUI serait construire sur du sable.

Cette discipline a payé immédiatement : le client attendait du `snake_case` quand le
plugin émet du `camelCase`, et les tests Swift « passaient » parce qu'ils avaient été
écrits contre la même hypothèse fausse. C'est la comparaison du tool avec la charge utile
réelle qui l'a révélé — pas les tests.

---

## Construire et lancer

```bash
cd packages/dsh-remote-swift
swift build
swift test

swift run DSHRemoteMac                    # l'application, sur le Mac

./.build/debug/dsh-remote-ctl http://127.0.0.1:3080 sante
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> sessions 20
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> journal <identifiant> 50
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> prompt <identifiant> "ton message"
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> annuler <identifiant>
```

### Le projet Xcode est versionné, et il ne porte aucune valeur personnelle

**Le schéma est partagé, donc versionné.** `xcodebuild -scheme DSHRemote` échouait sur
un clone neuf : Xcode ne crée les schémas qu'à l'ouverture du projet dans l'IDE, et
`xcodebuild -list` n'en annonçait aucun. Le schéma vit désormais dans
`DSHRemote.xcodeproj/xcshareddata/xcschemes/`, où git le voit.

**L'équipe de signature et l'identifiant de paquet ne sont plus dans le projet.** Ils
vivaient dans `project.pbxproj` : un identifiant de compte Apple en clair, et une
application que personne d'autre que son auteur ne pouvait signer (Xcode aurait tenté
de signer avec une équipe à laquelle l'utilisateur n'appartient pas). `Config/Base.xcconfig`
est versionné et porte les défauts ; `Config/Local.xcconfig`, **gitignoré**, porte les
valeurs personnelles :

```bash
cat > Config/Local.xcconfig <<'EOF'
DSH_TEAM = <ton identifiant d'equipe Apple>
EOF
```

Ce placeholder est volontairement non conforme à la forme d'un identifiant d'équipe :
`scripts/check-secrets.sh` refuse ces identifiants, et un exemple qui leur ressemblerait
ferait échouer le contrôle.

Sans ce fichier, l'application se construit **pour le simulateur** — qui ne signe pas.
Xcode ne réclame une équipe que pour un appareil réel. `#include?` et non `#include` :
c'est ce qui rend l'absence du fichier légitime plutôt que fatale.

Le chemin complet, du clone à l'application :

```bash
Scripts/construire-app-ios.sh --simulateur   # → .build/iphone/…/DSHRemote.app
Scripts/empaqueter-app-macos.sh              # → .build/macos/DSH Remote.app
Scripts/empaqueter-app-macos.sh --installer  # remplace /Applications et vérifie
```

Le premier porte l'exception ATS le temps du build et **restaure la source ensuite**,
même en cas d'échec (trap) : c'est ce qui empêche le nom du tailnet d'entrer dans un
commit accidentel.

**POURQUOI PASSER PAR LE SCRIPT, ET NON PAR UN `xcodebuild` DIRECT — mesuré DEUX
FOIS.** Un `xcodebuild` lancé sur un `-derivedDataPath` RÉUTILISÉ a produit un paquet
**sans aucune clé `NSAppTransportSecurity`**, alors que la phase « Exception ATS »
figurait bien dans le projet (en dernière position) et se déclarait exécutée. Le premier
build dans un chemin neuf l'injecte ; **le second, dans le même chemin, la perd** —
l'expérience a été refaite, avec le même résultat. Conséquence, constatée à l'écran : tous
les serveurs affichaient « **pas de DSH** », parce que chaque sonde vers un nom du tailnet
était refusée en `-1022`. Le script, lui, injecte dans la source **avant** de construire et
**vérifie le paquet produit** (`Print :NSAppTransportSecurity` → échec du build s'il
manque) : c'est le seul chemin qui ne peut pas mentir sur ce point. Le message d'erreur
`-1022` de l'application nomme désormais cette cause possible, faute de pouvoir la
prévenir.

**`--installer` : POURQUOI CETTE OPTION EXISTE.** Le paquet construit vit dans
`.build/macos/`, et rien ne le reliait à la copie de `/Applications` que l'utilisateur
lance réellement. Constaté : une copie installée à 02:16 continuait d'être lancée à 08:41
alors que le dépôt contenait déjà deux correctifs — l'écran montrait donc les anciens
défauts, et la cause était cherchée dans le code. **Deux applications du même nom, dont
aucune ne savait qu'elle était l'ancienne.** L'option ferme l'instance en cours, copie le
paquet (`ditto`, qui préserve la signature), **compare les empreintes SHA-256** du binaire
construit et du binaire installé, et prévient si l'exception ATS manque. Une copie
partielle ou refusée ne peut donc plus passer inaperçue.

### NE JAMAIS lancer le binaire du simulateur comme un programme macOS

Erreur facile à commettre, et son message ressemble à s'y méprendre à un plantage de
l'application :

```text
dyld: DYLD_ROOT_PATH not set for simulator program
Termination Reason: Namespace DYLD, Code 9
```

**Ce n'est pas un plantage.** C'est dyld qui refuse d'exécuter un binaire
**iOS-simulateur** hors du simulateur : aucune ligne de notre code n'a été atteinte, et
le rapport ne contient aucun cadre de `DSHRemote`. Reproduit sur les **deux**
architectures d'un binaire universel — ce n'est donc pas une question de processeur.

| Ce qu'il ne faut pas faire | Ce qu'il faut faire |
|---|---|
| `open` / double-clic sur le `.app` du conteneur du simulateur | `xcrun simctl launch <appareil> org.example.DSHRemote` |
| exécuter `.build/…/Debug-iphonesimulator/DSHRemote.app/DSHRemote` | Xcode ▸ Run avec une destination **simulateur** |
| viser « My Mac » avec cet exécutable | `swift run DSHRemoteMac` — l'application macOS, décrite ci-dessous |

L'application macOS existe donc **dans ce paquet**, et c'est elle qu'il faut lancer sur
le Mac : `Sources/DSHRemoteApp` ouvre `VuePrincipale`, la même vue que l'application iOS.

Le nom MagicDNS du Mac est celui que `tailscale status` affiche ; c'est aussi l'adresse
que `tailscale serve` publie.

L'essai d'intégration de l'écriture est **désactivé par défaut** : il exige un hôte
joignable et une session de travail, et il écrit pour de vrai (il consomme un tour de
modèle). Le jeton reste lu dans le coffre, jamais passé en argument :

```bash
DSH_REMOTE_ESSAI_ADRESSE=http://127.0.0.1:3099 \
DSH_REMOTE_ESSAI_SESSION=session-… \
  swift test --filter ecritureReelle
```

---

## Jeton d'appareil

Le tool lit le jeton dans `DSH_REMOTE_TOKEN`, et à défaut dans
`$DSH_HOME/.credentials.yaml` (la clé `dsh-remote/device-token`, écrite en `0600` par le
plugin). Il n'affiche **jamais** le jeton, seulement sa présence.

Pour l'application, le jeton ira dans le trousseau (Keychain) — jamais dans un fichier
de préférences, jamais dans un journal.

---

## Structure

```text
Sources/
├── DSHRemoteKit/          # bibliothèque partagée macOS + iOS — TOUT le code réutilisable
│   ├── Modeles.swift      # types du protocole, transport des enregistrements
│   ├── Ecriture.swift     # types de l'écriture (prompt, annulation, envoi en attente)
│   ├── Evenements.swift   # présentation des événements du journal
│   ├── Regroupement.swift # arbre des sessions par espace de travail
│   ├── EtatSession.swift  # pastilles et libellés d'état
│   ├── RappelsDeFin.swift # détection des fins de tour non vues (pastille verte)
│   ├── DecouverteServeurs.swift  # Macs du tailnet : découverte par l'hôte, ou locale sur macOS
│   ├── Tailscale.swift    # état de Tailscale sur cette machine
│   ├── FluxSession.swift  # WebSocket temps réel
│   ├── RemoteClient.swift
│   ├── ModeleApp.swift    # état de l'application — la vue ne parle jamais au réseau
│   ├── EtatMachine.swift  # l'état d'une machine : MÊMES MOTS au panneau latéral et sur sa page
│   ├── Vues.swift         # liste des sessions
│   ├── VueJournal.swift   # journal d'une session
│   ├── VueServeur.swift   # page d'un serveur — quatre bandes : identité, diagnostic, réglages, détail
│   ├── ParcoursDesEtapes.swift  # les quatre constats, en diagnostic ou en objectifs
│   ├── Demarches.swift    # publier le port, installer le plugin : les deux procédures partagées
│   ├── VueAjoutServeur.swift  # page « Ajouter un serveur »
│   ├── VueEcriture.swift  # composeur (écrire, interrompre)
│   └── VueReglages.swift  # réglages (adresse, jeton, suivi)
├── DSHRemoteCtl/          # tool de validation (macOS)
│   └── main.swift
└── DSHRemoteApp/          # application macOS : `swift run DSHRemoteMac`
    └── main.swift
Tests/
└── DSHRemoteKitTests/     # décodage des charges utiles réelles, écriture, rappels de fin
```

L'interface vit dans la **bibliothèque**, pas dans une cible d'application : c'est
la contrainte qui a déplacé le code (voir « Restructuration imposée par cette
contrainte »). Le paquet livre donc **deux exécutables macOS** — `dsh-remote-ctl` (le
tool de validation) et `DSHRemote` (l'application, qui n'ouvre que `VuePrincipale`) —
et l'application **iOS** vient du projet Xcode.

---

## Flux temps réel

```bash
./.build/debug/dsh-remote-ctl http://127.0.0.1:3080 flux <identifiant> 30
```

`FluxSession` s'appuie sur `URLSessionWebSocketTask`, fourni par la plateforme : ajouter
une bibliothèque WebSocket tierce à une application qui détient un jeton d'accès au
harness serait une surface d'attaque gratuite.

`sequenceConnue` porte le dernier `seq` observé. C'est ce qu'il faut passer à
`depuisSeq` en cas de reconnexion : le serveur ne renverra alors que ce qui manque.

Vérifié contre le serveur : 5 évènements et 3 deltas reçus en direct pendant que la
session écrivait, **0 doublon**, curseur de reprise conservé.

Dans l'application, `demarrerFlux` reprend au dernier `seq` déjà chargé — sans quoi la
base du flux recouvrirait la page affichée et le journal montrerait des doublons. Un
`seq` déjà présent est ignoré à l'application, et l'état du suivi est visible dans la
barre d'outils : un flux qui s'arrête en silence laisserait croire que la session est
inactive.

---

## Choix de conception

- **Aucun en-tête `Origin`.** Le serveur refuse en `403` toute requête qui en porte un —
  c'est sa barrière anti-navigateur. Le client en ajouterait un qu'il casserait son
  propre accès ; c'est commenté dans le code pour que personne ne « corrige » ça.
- **Aucun cookie, aucun cache.** `URLSessionConfiguration.ephemeral`, cache vidé,
  cookies refusés : un journal de session n'a rien à faire sur disque, et une réponse
  périmée induirait l'utilisateur en erreur.
- **Les erreurs disent quoi faire.** `jetonRefuse` dit « le jeton est absent, révoqué ou
  faux », pas « erreur 401 ».
- **La version du protocole est vérifiée, pas supposée.** Un serveur qui annonce une
  version inconnue provoque un refus explicite.
- **Les types Swift sont en français**, les champs du fil en `camelCase` : les
  `CodingKeys` font la correspondance et sont la seule source de vérité des noms.
- **Un refus de l'hôte n'est jamais réduit à un statut HTTP.** Le corps JSON
  (`erreur`, `code`, `detail`) est décodé en `ErreurRemote.refusServeur`, puis traduit
  par `RefusEcriture`. « Aucun modèle n'est choisi pour cette session » se corrige ;
  « HTTP 409 » ne dit rien.

---

## Ce qui est prouvé

| Affirmation | Preuve |
|---|---|
| Le paquet compile pour macOS 14 et iOS 17 | `swift build` |
| Le protocole réel se décode | tests verts sur des charges utiles copiées du serveur |
| Le bout en bout fonctionne | `dsh-remote-ctl <tailnet> sessions` liste 102 sessions avec titres, compteurs et dates |
| Le journal se lit | `dsh-remote-ctl <tailnet> journal <id> 8` affiche les enregistrements typés |
| **L'écriture fonctionne depuis le client** | `dsh-remote-ctl <adresse> prompt <id> "…"` → `accepté: true`, `reprise: true` sur une session froide |
| **L'envoi est idempotent** | essai d'intégration `swift test --filter ecritureReelle` : deux envois du même `requestId`, deux `202`, **un seul** message dans le journal |
| **L'annulation fonctionne depuis le client** | `dsh-remote-ctl <adresse> annuler <id>` → `annulé: true` |
| **Le refus est traduit, pas affiché en code** | test « Un refus d'écriture est traduit, jamais affiché en code » |
| **Le journal s'ouvre vraiment dans l'application** | simulateur : « Journal (41 affichés) » là où l'écran restait vide ; côté hôte, `POST /v1/session/<id> -> 200` |
| **La liste se redessine quand l'état change** | avant correction : serveur à `inactif` / 30 évts, écran figé sur l'animation et « 27 évts » une minute plus tard ; après : 38 évts et la pastille à jour |
| **La pastille verte apparaît à la fin d'un tour non vu** | capture du simulateur : carrés orange pendant le tour, **point vert** après, sans avoir ouvert la session |
| **Elle s'efface quand on ouvre la session** | ouvrir la session puis revenir à la liste : plus de vert, et il ne revient pas |
| **Le repos n'affiche plus rien** | capture du simulateur : onze sessions chargées, aucune pastille |
| **La décision attendue devient un point orange** | chaîne mesurée sur une charge utile RÉELLE : `attendReponse: true` → `EtatSession.attendReponse` (la valeur que la pastille rend), pendant qu'une question d'un tool est en attente |
| **Le flux alimente l'écran ouvert** | la même capture passe de 41 à 48 enregistrements pendant qu'une autre session écrit |
| **Le composeur est rendu** | capture du simulateur : champ « Écrire à cette session… », sélecteur de mode, bouton d'envoi |
| **L'hôte publie la liste des Macs du tailnet** | `dsh-remote-ctl <adresse> serveurs` → 3 Macs ; le PC Windows et l'iPhone sont écartés |
| **Les espaces viennent du registre de l'hôte** | `dsh-remote-ctl <adresse> espaces` → 7 espaces, du plus récent au plus ancien, avec leur nombre de sessions |
| **Espaces par création, sessions par activité** | 3 tests : un espace ancien mais très actif reste sous un espace récent ; dans un espace, la session la plus active passe devant ; départage stable à date égale |
| **Un espace vide est représenté** | 6 tests sur les charges utiles de l'hôte : espace sans session marqué `sansSession`, appartenance par identifiant et non par chemin, « Sans espace » en dernier, repli sur `cwd` sans registre |
| **L'iPhone CONSOMME la découverte** | simulateur iPhone 17 Pro : les 3 Macs s'affichent avec icône et état, « hôte interrogé » sur la machine qui répond — aucun processus exécuté par l'application |
| **La découverte survit à un environnement d'application** | app empaquetée lancée comme le Finder la lance : `[sonde] debut : 3 candidat(s)` puis `1 serveur(s) DSH sur 3` — contre `aucun Mac decouvert` avant le correctif |
| **Un CLI qui échoue en code 0 ne devient pas « tailnet vide »** | test « Un CLI qui échoue en code 0 ne doit PAS devenir « tailnet vide » », sur la sortie réelle du CLI (`Tailscale.CLIError error 3` sur stdout, code 0) |
| **L'exception ATS couvre tout le tailnet** | même requête vers un autre Mac, en boîtier applicatif : `-1022` avec un nom de machine, `-1004` avec le domaine du tailnet |
| **Une machine éteinte n'est ni visée ni sondée** | adresse mémorisée pointant sur un Mac éteint : `2 candidat(s)` sondés au lieu de 3, et fichier de diagnostic **inchangé** (aucune requête émise) là où l'ancienne version y laissait un `-1001` après 21 s |
| **Le statut des serveurs se résout** | simulateur : « DSH · hôte », « pas de DSH », « hors ligne » — la sonde des machines en ligne n'est plus retenue par la machine morte |
| **Une bascule de serveur exige une preuve** | 7 tests sur la décision pure ; sur capture, l'avis « ne répond pas » a disparu alors que l'application était connectée à l'adresse qu'il prétendait morte |
| **Les commandes d'aide se copient** | capture du simulateur : deux encadrés `tailscale serve …` avec leur bouton, et le pavé `-1004` n'est plus affiché |
| **La commande d'aide est VRAIE** | `tailscale serve --bg --http=80 http://127.0.0.1:3080` passée sur la machine : `serve status --json` **identique** avant/après — l'ancienne forme (`--bg 80 <url>`) était invalide |
| **La vérification est mesurée, pas supposée** | découverte 44 ms, sonde complète 16 ms, verdict posé **0,3 s** après le lancement ; requêtes 1,2 à 15 ms selon la cible |
| **Un port 80 occupé par autre chose est reconnu** | MacMini renvoie `HTTP/1.1 404 Not Found` (sans `Server`) : message et commandes affichés, là où l'écran montrait « réponse inattendue (HTTP 404) » ; 1 test couvre les deux formes |
| **Le jeton est sur la page de l'hôte, pas dans les réglages** | capture iPhone : « Jeton d'appareil de cet hôte » + état « jeton complet (43 caractères) » sur la page ; les Réglages ne le contiennent plus |
| **Les Réglages ne contiennent plus rien d'une machine** | capture iPhone : une phrase qui l'explique, puis les deux interrupteurs de sessions (préférences d'affichage, communes à toutes les machines) |
| **La page d'un serveur remplace le diagnostic dans le panneau latéral** | capture iPhone (`--page-seule`) : état, adresse, actions et jeton sur la page ; le panneau ne garde que pastille, légende et nom |
| **Une sonde annulée n'écrase plus le verdict** | journal : `fin : 1 serveur(s) DSH sur 2` puis `fin : 0` avant correction ; après, la sonde annulée ne publie rien et la page affiche « DSH · hôte interrogé » |
| **La page dit que le plugin manque, et donne la démarche** | capture iPhone de la page de MacMini (alors que l'app vise une autre machine) : constat nommé, 3 étapes, bloc `cordis.patch.yml` copiable, vérification `curl` |
| **Le diagnostic de santé d'un serveur** | captures iPhone : conclusion (« Il reste une étape : « … » ») puis les quatre constats, sans verrou ; sur un Mac hors ligne, l'étape 2 avec ses commandes et les suivantes « à vérifier » |
| **Les étapes suivantes sont grisées** | capture iPhone : frontière (étape 2) avec sa méthode, étapes 3 et 4 grisées avec un cadenas et « après l'étape N », sans détail |
| **La page d'un serveur est structurée en quatre bandes** | 3 captures macOS (`--page-seule`) : prêt, pas de DSH (MacMini), hors ligne — l'état est dit UNE fois, l'action proposée peut aboutir, les réglages sont repliés |
| **Les mots de l'état sont partagés** | 2 tests sur `EtatMachine` : la vignette abrège, la page dit la phrase entière, et les deux portent le même ton ; la conclusion suit l'état |
| **Tailscale a quitté le panneau latéral** | capture macOS (la colonne commence aux serveurs) et capture iPhone NEUF — conteneur vidé : la liste vide offre « Ajouter un serveur », qui porte l'étape 1 et son bouton d'installation |
| **« Espaces de travail », et non « Workspaces »** | captures macOS et iPhone : le titre de la section est en français, comme le reste de l'interface |
| **Un jeton n'est accusé que s'il a été présenté** | test : `.incomplete` (« hors ligne ») ne met PAS `jetonRefuse` ; `.jetonInvalide` et un `401` le mettent |
| **La page « Ajouter un serveur »** | capture iPhone (`--ajout --page-seule`) : étape 1 constatée, étapes 2-4 à faire avec leurs commandes, chacune disant sur quelle machine |
| **Le parcours d'un serveur, en trois étapes** | captures iPhone : MacMini (étapes 1-3 vertes, 4 à faire + méthode) et un Mac hors ligne (étapes 2 à faire, suivantes « à vérifier ») ; 8 tests |
| **Le diagnostic appartient à la machine** | `404` observé par la sonde → procédure d'installation ; `-1004` → procédure de publication ; vérifié par capture sur une machine NON visée |
| **Une réponse en vol n'écrit pas dans une autre cible** | 2 tests : la bascule invalide le vol, une liste en retard est refusée ; 87 tests au total |
| **Le jeton est par hôte** | 3 tests : chaque hôte rappelle le sien, celui de l'hôte local n'est pas recopié, effacer n'efface que le sien |
| **Deux délais, mesurés** | `sante` 1,6-4,1 ms → plafond 5 s ; liste 4,06 s à froid → plafond 30 s ; un plafond unique de 8 s avait refusé une connexion valide à 8055 ms |
| **La cible se remplace en un point** | une seule ligne écrit `cible` ; 5 transitions nommées, 5 tests sans réseau ; en vrai, plus d'oscillation d'adresse au démarrage |
| **Les états corrélés sont remplacés par deux valeurs** | 5 tests d'invariants verts (77 au total) ; en vrai, verdict posé en 0,4 s après le remaniement |
| **Le compte de la section ne compte que l'utilisable** | capture iPhone : « Serveur DeepSeek Harness — 1 joignable », alors que deux machines sont en ligne (l'une n'a pas DSH) et que les trois sont affichées |
| **Le verdict ne clignote plus au rafraîchissement** | capture prise **pendant** une sonde (2ᵉ `sonde] debut` du journal) : « DSH · hôte », « pas de DSH » et « hors ligne » restent affichés — l'ancien code les repassait à « vérification… » à chaque sonde |
| **Un échec devenu faux est effacé et la connexion rejouée** | `relancerSiLaCibleSertDsh` : si la sonde dit que la machine visée sert DSH, l'erreur affichée disparaît et `connecter()` est retenté |
| **Un `xcodebuild` sur DerivedData réutilisé perd l'exception ATS** | reproduit deux fois : le premier build dans un chemin neuf l'injecte, le second dans le même chemin la perd → tous les serveurs en « pas de DSH » (`-1022`) ; d'où le passage obligatoire par `Scripts/construire-app-ios.sh`, qui vérifie le paquet |
| La liste vide dit pourquoi | `/v1/serveurs` rend `diagnostic` quand la liste est vide ; 5 tests couvrent les charges utiles de l'hôte |
| Chaque icône rendue EXISTE | test « Chaque icône rendue est un symbole SF qui existe vraiment » — il a mis en évidence que `macbook.air`, `macbook.pro` et `imac` n'existent pas |
| Les refus sont respectés | `401` sans jeton, `403` avec `Origin`, `404` sur identifiant inconnu |
| **L'application macOS existe et fonctionne** | `swift run DSHRemoteMac` : fenêtre 1100×720 **à l'écran** (`isOnScreen=true`), Tailscale connecté, serveurs listés, **11 sessions** groupées en 4 espaces |
| **La fenêtre reste derrière sans activation explicite** | mesuré : fenêtre créée mais `isOnScreen=false` ; `setActivationPolicy(.regular)` + `activate` la fait apparaître |
| **Le binaire du simulateur lancé sur macOS est refusé par dyld** | reproduit : `DYLD_ROOT_PATH not set for simulator program`, sur les deux architectures, aucun cadre de `DSHRemote` |
| L'application fonctionne sur iOS | simulateur iPhone 17 Pro : liste des sessions connectée à la vraie instance |
| Le code compile pour un iPhone réel | `swift build --triple arm64-apple-ios18.0 --sdk <iphoneos>` |
| Xcode compile et lie pour iOS | `xcodebuild -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED` |
| Le projet Xcode produit une app installable | `DSHRemote.app` avec `Info.plist`, identifiant `org.example.DSHRemote`, installée et lancée dans le simulateur |
| **Le projet Xcode ne produit PAS d'app macOS native** | `project.pbxproj` : `SDKROOT = iphoneos`, `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"` |
| Le simulateur ne lit pas le coffre du Mac | conteneur en bac à sable : l'app affiche « Aucun jeton d'appareil » |
| L'installation sur l'iPhone exige une action manuelle | `xcodebuild` échoue : appareil non enregistré, aucun profil pour `org.example.DSHRemote` |
| L'application est INSTALLÉE sur l'iPhone | `devicectl device info apps` liste `DSH Remote — org.example.DSHRemote — 0.1` |
| Elle est signée par l'équipe du propriétaire | `codesign -dv` : `TeamIdentifier=<équipe du propriétaire>`, `embedded.mobileprovision` présent |
| L'IP tailnet avec port ne sert RIEN | `http://100.101.102.103:3080` → `000` ; le nom MagicDNS → `200` |
