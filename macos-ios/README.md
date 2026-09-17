# dsh-remote-swift — client Swift multiplateforme

Client **Swift natif** (macOS et iOS) du plugin [`dsh-remote`](../../plugins/dsh-remote/).
Une seule bibliothèque partagée porte le protocole, le transport et les modèles ; les
deux applications la consomment telle quelle.

MISE À JOUR — jalons 2, 3 et l'écriture livrés : voir [Application](#application),
[Flux temps réel](#flux-temps-reel) et
[Écriture](#ecriture-repondre-a-l-agent-et-l-interrompre).

---

## Index — contrat, procédure, mesures, limites

**POURQUOI CET INDEX.** Ce document est un journal de bord autant qu'une référence :
chaque essai sur l'appareil, chaque défaut corrigé y a laissé sa mesure — c'est ce qui
en fait la valeur, et c'est aussi ce qui rend difficile de trouver « que garantit le
client ? » quand on arrive. Les quatre familles sont nommées ici.

| Famille | Où | Sections |
|---|---|---|
| **Contrat** (normatif) | ce que le client promet et suit | `Application` (l'interface et ses règles), `Flux temps réel` (le protocole, la reprise, le battement de cœur), `Jeton d'appareil`, `Choix de conception` |
| **Procédure** (à exécuter) | installer, construire, essayer | `Construire et lancer`, `Installer sur l'iPhone`, `Amorce par fichier`, `Essai sur le simulateur iOS`, `Structure` |
| **Mesures** (datées, sans autorité) | pourquoi une règle est ce qu'elle est | `Le suivi de l'activité`, `L'arrière-plan`, `La reconnexion est AUTOMATIQUE`, `Le battement de cœur`, `La configuration réseau est PARTAGÉE`, `Vue d'un défaut trouvé en regardant`, `Ce que l'essai a appris` |
| **Limites ouvertes** | ce qui reste à prouver | `Ce qui reste non prouvé`, `Ce que cette route ne fait pas` (côté hôte), les notes « non mesuré » des sections de mesure |

**CE QUI N'EST PAS DANS CE DOCUMENT** : le format des échanges (charge utile
d'appairage, corps JSON, en-têtes) appartient au README du plugin — ici, c'est le
CLIENT qui est décrit, et une divergence entre les deux moitiés est un défaut que les
fixtures partagés attrapent.

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

### Icône : le sifflet arrondi

L'icône retenue le 14 septembre 2026 est une silhouette de sifflet au corps rond,
avec un bec montant et une encoche. Le dessin est un aplat bleu DeepSeek
`#4D6BFE`, sans détail supplémentaire. Son contour est défini dans
[`Scripts/generer-icone.py`](Scripts/generer-icone.py), variante `arrondi`,
désormais utilisée par défaut.

Le catalogue iOS/iPadOS contient trois PNG de 1024 × 1024 : bleu sur blanc pour
l'apparence claire, bleu sur fond transparent pour l'apparence sombre et blanc
sur noir pour le gabarit teinté. Les deux dernières formes suivent les
[consignes Apple pour le catalogue d'icônes](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).
Le paquet macOS reprend le même signe dans une tuile arrondie avec marges
transparentes, exportée en ICNS.

Commandes exécutées depuis la racine du dépôt :

```bash
python3 packages/dsh-remote-swift/Scripts/generer-icone.py --apercu --icns packages/dsh-remote-swift/.build/macos/DSHRemote.icns
bash packages/dsh-remote-swift/Scripts/empaqueter-app-macos.sh
```

**Pillow est un prérequis, et il n'est pas dans le `python3` du PATH sur cette
machine — mesuré le 14 septembre 2026.** `generer-icone.py` dessine le sillon
lui-même et le remplit avec Pillow (aucun moteur SVG n'est requis). S'il manque,
le script s'arrête sur `[icone] Pillow est requis` et, `set -euo pipefail` aidant,
le paquet macOS n'est **pas assemblé du tout**. Or les deux interpréteurs de la
machine ne se valent pas : `/opt/homebrew/bin/python3` (3.14.7, celui du PATH) n'a
pas Pillow, `/usr/bin/python3` (3.9.6) porte Pillow 11.1.0. La commande qui marche
ici, sans rien installer :

```bash
PATH="/usr/bin:$PATH" bash packages/dsh-remote-swift/Scripts/empaqueter-app-macos.sh
```

Vérifications : aperçu inspecté jusqu'à 40 px ; dimensions, alpha, bleu exact et
niveaux de gris contrôlés ; dix représentations ICNS réextraites de 16 à 1024 px ;
paquet macOS reconstruit et signature vérifiée ; compilation du simulateur réussie,
avec `AppIcon` présent pour les familles iPhone et iPad. Les vérifications du dépôt
passent : secrets, syntaxe, 194 tests de plugins et 341 tests Swift. Ces commandes
ne réinstallent pas les copies déjà présentes sur les appareils.

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

2. **L'adresse est le nom MagicDNS, sans port — et sa lisibilité dépend du paquet.**
   `tailscale serve` publie l'instance sur le **port 80 du nom MagicDNS** ; le harness,
   lui, n'écoute que sur la boucle locale, donc `http://100.x.y.z:3080` **ne répond
   pas** (mesuré : `000`). Voir le tableau de « Installé sur l'iPhone » plus bas.

   Reste App Transport Security : il n'impose TLS qu'aux **noms de domaine qualifiés**,
   et l'exception qui les autorise en clair n'est posée que par les scripts du dépôt
   (`Scripts/construire-app-ios.sh` côté iOS, `Scripts/empaqueter-app-macos.sh` côté
   Mac), à partir de `Config/DomaineTailnet` — un fichier local, absent d'un clone.
   Mesuré : un `xcodebuild` direct produit un paquet **sans** exception, qui refuse
   toutes les machines du tailnet en `-1022`.

   L'application ne le suppose donc plus, elle le **lit** : le champ et son pied de page
   s'adaptent à ce que l'Info.plist du paquet en cours autorise (`ExceptionATS`). Sans
   exception, elle conseille `https://…` — à publier avec
   `tailscale serve --https 443`, sans aucune exception à poser — ou
   `Scripts/construire-app-ios.sh`, qui pose l'exception pour votre tailnet. Avec
   l'exception, elle conseille `http://<machine>.<tailnet>.ts.net`, et le dit.

### Le schéma suit ce que le paquet autorise — et l'hôte ANNONCE le sien

**Le défaut, et c'était le plus gros obstacle à la distribution.** Trois endroits
fabriquaient une adresse en écrivant `"http://" + hote` : le QR d'appairage, la liste
des machines découvertes, la saisie manuelle. Dans un paquet **sans** exception ATS —
c'est-à-dire dans tout clone du dépôt — ces trois chemins produisaient une adresse que
le système refuse (`-1022`), **appairage compris** : on ne pouvait même pas se connecter
pour corriger.

**Deux règles, et la plus sévère gagne** (`AdresseMachine`, pure, éprouvée avec les
plists qu'on veut) :

| Source | Ce qu'elle dit | Exemple |
|---|---|---|
| Le paquet (`ExceptionATS`, lu dans l'Info.plist **en cours d'exécution**) | ce qui est seulement **possible** | sans exception → `https://mac…` ; avec → `http://mac…` |
| La charge utile du QR (5ᵉ segment, omis quand il vaut `http`) | ce que l'hôte **annonce** | `dshremote://mac…/code/v1/<secret>/https` |

Un hôte publié en clair ne fait donc **jamais** viser le clair à un paquet qui l'interdit :
l'adresse serait refusée avant de partir, et le message parlerait de transport au lieu du
vrai problème. Et un hôte publié en HTTPS est suivi, exception ou pas.

**Où le schéma de l'hôte est-il lu ?** Dans `tailscale serve status --json`, par une
fonction PURE du plugin (`publicationDepuisServe`), éprouvée sur la forme **mesurée** de
cette installation (publication en clair sur 80) et sur la forme HTTPS documentée par
Tailscale — celle-là **non mesurée ici**, donc lue sur le drapeau du port plutôt que
supposée. Sans binaire, sans publication ou devant une sortie inattendue, on retombe sur
le clair : le comportement d'avant, jamais une adresse inventée.

**Le schéma n'est pas une identité.** `IdentiteHote.cle` porte désormais le **nom et le
port** — plus le transport : la même machine en `http` et en `https` est LA MÊME. Sans
cela, passer le serveur en HTTPS faisait perdre le jeton rangé pour l'adresse en clair,
et la machine jointe n'était plus reconnue. Les jetons rangés sous l'ancienne clé sont
retrouvés, réécrits sous la clé neuve, et l'ancienne entrée est effacée : la migration ne
demande aucun geste (`AdresseMachineTests` le prouve sur les deux chemins).

**Ce qui reste à faire à la main, et c'est dit** : publier en HTTPS
(`tailscale serve --https 443 http://127.0.0.1:3080`), puis **supprimer l'exception** —
c'est-à-dire ne pas créer `Config/DomaineTailnet`, ou retirer la phase « Exception ATS »
du projet. Tant que l'exception est là, l'application vise le clair : c'est ce que le
paquet autorise, et le lui cacher serait pire.

**Ce qui n'a PAS été mesuré** : la publication en HTTPS elle-même (`tailscale serve
--https 443`) et la confiance d'iOS dans ce certificat. Cette machine publie en clair sur
le port 80 ; la branche HTTPS du lecteur est écrite d'après la documentation et éprouvée
par des vecteurs, pas par un aller-retour réel.

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
| L'ordre d'affichage des machines | joignables d'abord ; à joignabilité égale, les machines **prêtes** (qui servent DSH) avant celles restant à configurer ; puis par nom (`DecouverteServeurs.ordonnerPourAffichage`) |
| La liste s'affiche avec icône, état, et « hôte interrogé » | `VueListeSessions` |
| Une liste vide dit POURQUOI | `ModeleApp.messageListeVide`, qui distingue « l'hôte ne voit personne » de « cette plateforme ne peut pas voir » |
| Le tout est éprouvable sans interface | `dsh-remote-ctl <adresse> serveurs` |

**L'ORDRE DU CARROUSEL NE DÉPEND QUE DES MACHINES — JAMAIS DE LA SÉLECTION.** Deux
clés, dans cet ordre : la machine **joignable** avant l'éteinte (une machine éteinte
ne peut rien rendre, quelle que soit sa configuration), et à joignabilité égale,
celle qui **sert DSH** avant celle qui reste à configurer — c'est celle-là qu'on vient
ouvrir. À égalité sur les deux, le nom. La vignette « Ajouter » est rendue **après**
la liste, donc après les éteintes, et n'entre pas dans ce tri.

**UN TRI PAR « MACHINE CONNECTÉE D'ABORD » A EXISTÉ ICI, ET IL A ÉTÉ RETIRÉ.** Il
répondait à une remarque juste — la vignette **cochée** n'était pas la première — mais
il produisait le défaut qu'on veut éviter : **toucher une vignette CONNECTE**, donc la
machine touchée sautait en tête à l'instant même du toucher, le contenu se décalait
sous le doigt et la **barre de défilement s'agitait à chaque connexion**. Une liste
qu'on parcourt du doigt ne bouge pas parce qu'on l'a touchée : l'ordre ne dépend ni
du dernier choix, ni de l'heure, ni de l'état de connexion. Trois tests le
verrouillent — `ordreJoignablePuisPret`, `leChoixNeReordonnePasLeCarrousel`,
`machinePreteAvantAConfigurer`.

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
| Terminal | 3 machines | 3 machines |
| Environnement d'application (Finder) | `aucune machine decouverte` | **3 machines** |

**DEPUIS, LA RÈGLE A CHANGÉ, ET CES COMPTES AVEC ELLE.** La découverte ne retenait que
les machines `macOS` ; elle retient maintenant **toutes celles qui peuvent héberger
DSH** — macOS, Windows, Linux — et écarte iOS et Android, qui n'exécutent pas de
processus. Le même tailnet en rend donc **4** : les trois Macs et `MiBook` (`OS`
`windows`), mesuré par `dsh-remote-ctl serveurs`. Le motif est écrit plus bas, dans
« Un PC Windows est un serveur DSH légitime ».

Le plugin hôte n'a jamais eu ce défaut : en JavaScript, `JSON.parse` **lève**, donc la
route essaie le candidat suivant et rapporte « sortie illisible ». C'est le code Swift qui
se fiait au code de sortie.

**Résultat mesuré** : sur le simulateur iPhone 17 Pro, la liste des machines du tailnet
s'affiche — avec icône, état en ligne/hors ligne, et la mention « hôte interrogé » sur
celle qui répond. L'application n'exécute aucun processus : elle lit la
réponse de l'hôte. Sur le Mac, l'application empaquetée lancée dans un environnement
d'application trouve les **mêmes machines** et sonde lesquelles servent DSH (`1 serveur(s)
DSH sur 3` au moment de la mesure — les autres n'ont rien qui écoute, ou sont hors
ligne).

#### Un PC Windows est un serveur DSH légitime

**Le défaut, rapporté par le propriétaire** : « je constate qu'il y a un serveur windows
qui n'est pas listé, or le serveur DSH est universel non ? c'est juste le remote qui est
macOS ou iOS ». Il a raison sur les deux points, et la découverte était fautive.

Elle ne retenait que les machines `OS == "macOS"`, dans **deux** endroits — le plugin de
l'hôte (`dynamic/tailscale.js`) et la découverte locale du client
(`DecouverteServeurs.analyserRacine`). La justification écrite était : « proposer un PC
Windows ou un iPhone comme serveur DSH serait une promesse que l'installation ne peut pas
tenir ». Elle confondait deux choses :

- **ce qui ne peut pas héberger DSH** : iOS, iPadOS, Android, tvOS — ces systèmes
  n'exécutent pas de processus, et un iPhone ne fera jamais tourner un harness Node ;
- **ce qui peut l'héberger** : macOS, **Windows**, Linux. DSH est un harness Node, et il
  est cross-platform jusqu'au bac à sable (`dsh-sandbox-windows-acl` est publié pour
  Windows). C'est l'**application** qui est macOS et iOS — pas l'hôte.

La règle est donc devenue une **liste blanche** — `macOS`, `windows`, `linux` — écrite
aux deux endroits, et **identique** : deux listes qui divergeraient feraient apparaître
une machine côté hôte et pas côté client. Elle ne promet pas qu'une machine serve DSH :
elle dit qu'elle *pourrait* l'héberger, et la sonde tranche — une machine qui ne répond
pas s'affiche « pas de DSH », ce qui est exactement ce qu'on sait d'elle.

**Mesuré sur le tailnet du propriétaire**, là où le défaut a été vu :

```text
$ dsh-remote-ctl serveurs
Machines sur le tailnet : 4
  en ligne    MacBook Air de Camille
  en ligne    MacMini
  hors ligne  MacBook Pro de Camille
  hors ligne  MiBook                    ← OS `windows`, absent avant la correction
```

L'iPhone (`OS` `iOS`) reste écarté, et c'est la seule exclusion qui subsiste — celle qui
était juste.

**TROIS CORRECTIONS DE PLATEFORME SONT VENUES AVEC**, parce que la découverte n'était pas
la seule ligne écrite pour un Mac :

1. les **candidats du CLI Tailscale** du plugin étaient tous POSIX ; Windows reçoit
   `…\Tailscale\tailscale.exe`, et un **nom nu** est désormais essayé par le `PATH` sur
   les trois systèmes (un nom nu n'est pas soumis au test d'existence : `access()` résout
   relativement au dossier courant, pas dans le `PATH`) ;
2. **`homedir()` remplace `process.env.HOME`** pour résoudre `~/.dsh` : la variable
   n'existe pas sur Windows, où le profil est dans `USERPROFILE`. Le repli `/tmp` d'avant
   y aurait résolu `C:\tmp\.dsh` — un dossier vide, donc **zéro session, sans erreur** ;
3. le vocabulaire : l'application ne dit plus « Mac » là où la machine peut être un PC
   (« Chercher une machine », « Cette machine est visible », « Allumez cette machine-là »,
   « sur l'hôte »). Un libellé qui nomme un Mac sur la page d'un PC est un mensonge, et
   c'est précisément ce que ce dépôt traque.

**CE QUI N'A PAS ÉTÉ ÉPROUVÉ, ET QUI EST ÉCRIT COMME TEL** : aucun hôte Windows n'a
chargé ce plugin ici. Le chemin du CLI, les candidats et `homedir()` sont écrits d'après
la documentation des plateformes, pas mesurés ; ce qui EST mesuré, c'est que `OS ==
"windows"` est retenu par les deux découvertes, et que la liste réelle gagne `MiBook`.

**Et le code du plugin n'est pas rechargé à chaud** : la correction de la règle ne prend
effet qu'au **redémarrage du harness** (`dsh web`). La découverte locale du client, elle,
suffit à voir `MiBook` dès la reconstruction de l'application.

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

#### Ce qui ne repart plus toutes les quinze secondes : deux mesures

Les trois boucles ci-dessus avaient un défaut commun, invisible à l'écran : **elles
reposaient la même question à cadence fixe**, même quand la réponse ne pouvait pas
avoir changé.

| Ce qui partait | Cadence | Ce qui part maintenant |
|---|---|---|
| La liste des sessions **en entier** (~115 Kio mesurés sur l'installation : 172 sessions × ~685 o) | 20×/min | **rien** quand rien n'a bougé : `304`, 0 octet (voir le README du plugin, § « La liste est CONDITIONNELLE ») |
| `GET /v1/sante` sur **chaque Mac en ligne** | toutes les 15 s | seulement quand **l'ensemble des machines en ligne** change — et le geste « Revérifier » reste, lui, inconditionnel |
| `GET /v1/serveurs` et `GET /v1/espaces` | toutes les 15 s | les mêmes requêtes, mais sur **un client déjà construit** (une session, au lieu d'un handshake neuf par appel) |

**L'EMPREINTE QUI DÉCIDE DE LA SONDE EST CELLE DE L'ENSEMBLE SONDÉ**, pas de la liste
entière : une machine **hors ligne n'est jamais interrogée** (délibéré, mesuré plus
haut), donc son apparition ou sa disparition ne change rien aux requêtes qui partent.
Comparer la liste entière relançait un cycle complet pour un Mac éteint — précisément
ce qu'on cherchait à éviter.

**Trois tests le tiennent sans réseau** (`SondeConditionnelleTests.swift`) : une liste
inchangée ne resonde pas, une machine en plus ou en moins resonde, et **changer de cible
oublie ce qui a été sondé** — le constat appartenait aux machines que l'hôte précédent
voyait.

**CE QUI N'A PAS CHANGÉ** : la politique de délais (`delaiSante`, `delaiListe`,
`delaiHote`) est intacte. Le registre de clients est **clé par `(adresse, délai)`** : deux
appels qui n'ont pas la même patience ne partagent jamais le même objet — les fusionner
rendrait la question courte aussi patiente que la lecture lourde, c'est-à-dire ferait
attendre trente secondes pour apprendre qu'une machine est muette.

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
serveur, les cinq lignes **constatent** l'état d'une machine — on veut tout
savoir d'un coup, et seule celle qui bloque porte sa méthode dépliée. Sur la page
« Ajouter un serveur », elles **listent** un travail à faire, dans l'ordre, et le
verrou n'y traverse pas les deux côtés (voir plus bas).

| Page | Lecture | Verrou |
|---|---|---|
| un serveur | **diagnostic de santé** | aucun : un diagnostic qui cache la moitié de ses conclusions n'en est pas un |
| « Ajouter un serveur » | **objectifs à réaliser** | les étapes suivant celle qui bloque sont grisées |

Le diagnostic s'ouvre sur sa **conclusion** — « Ce serveur est prêt. » / « Il reste
une étape : « … » » / « Vérification en cours… » — parce que « ce serveur est-il
utilisable ? » est la question, et les cinq étapes la démonstration. Le titre de
l'étape restante est **cité tel quel** : le mettre en minuscules abîmait les noms
propres (« Cette machine est visible » devenait « cette machine est visible », constaté sur
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
| 2. La machine à ajouter est sur le tailnet | sur cette machine-là : installer Tailscale, le connecter, `tailscale status` |
| 3. Le port de DSH y est ouvert | sur cette machine-là : `tailscale serve --bg --http=80 http://127.0.0.1:3080` |
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

#### Le parcours d'un serveur : cinq étapes, et la méthode pour chacune

Demande du propriétaire : « une ligne de goal à franchir », avec, pour chaque
étape non remplie, la méthodologie pour y arriver. La page d'un serveur montre
donc un **parcours** — et non plus seulement un diagnostic.

| Étape | Ce qu'elle veut dire | D'où vient son état |
|---|---|---|
| 1. Tailscale est connecté sur cet appareil | il porte une adresse de tailnet | une CONSTATATION locale : `getifaddrs`, plage `100.64.0.0/10` |
| 2. Cette machine est visible | elle est en ligne sur le tailnet, donc la découverte la propose | un FAIT de Tailscale (`Online`), lu, jamais mesuré par l'application |
| 3. Le port de DSH est ouvert | quelque chose répond sur son port 80, publié par `tailscale serve` | la sonde : un `404` prouve que le port est ouvert |
| 4. Le plugin `dsh-remote` est installé | DSH Remote y répond | la sonde : `200` ou `401` |
| 5. **Cet appareil est appairé** | il a son propre jeton pour cette machine | le TROUSSEAU, pour cet hôte — et un refus (`401`) le dit aussi |

**LA CINQUIÈME ÉTAPE A RÉPARÉ LE PIRE MENSONGE DE L'APPLICATION.** La sonde ne
partait pas sans jeton : il y avait, dans `sonderLesServeurs`, une garde
`guard jeton.count == 43` dont la raison — « sans jeton, aucune sonde n'est
possible » — était **fausse**. `Sonde.interroger` compte déjà un `401` comme
« DSH est là », puisqu'un jeton refusé PROUVE que le service a répondu. Le prix
de la garde : un appareil non appairé ne sondait rien, publiait un verdict VIDE,
et la vignette en concluait « pas de DSH » — donc envoyait installer un plugin
**déjà installé** sur une machine parfaitement prête. C'est le cas le plus
fréquent : on installe l'application sur un téléphone, le Mac tourne depuis
longtemps. La page se contredisait même à l'intérieur d'elle-même : la pastille
affirmait « pas de DSH », la conclusion disait « Vérification en cours… ».

Ce que la machine a, c'est DSH ; ce qui manque est ailleurs, et le mot le dit
maintenant : **« à appairer »** (vert — la machine va bien) ou **« jeton refusé »**
(orange — le secret rangé n'est pas celui de cette machine). La distinction est
dans le modèle (`ModeleApp.etatAppairage(pour:)`), pas dans la vue, et
`EtatAppairage` porte trois cas — `appaire`, `absent`, `refuse` — parce que les
deux derniers n'ont pas le même remède.

**LA PREMIÈRE ÉTAPE AVAIT ÉTÉ AJOUTÉE DE LA MÊME FAÇON**, à la demande du
propriétaire : « j'ai oublié un goal avant, le fait que Tailscale est connecté ».
Elle manquait effectivement — sur un iPhone sans Tailscale, les trois autres ne
peuvent pas être franchies, et le parcours commençait pourtant par elles. Quand
elle n'est pas franchie, **les trois du milieu passent à « inconnue »** : une
liste de machines peut dater d'avant la coupure, et une sonde avoir répondu il y a
une minute — affirmer quoi que ce soit depuis un appareil qui ne peut plus rien
joindre serait parler du passé. **L'appairage, lui, ne se déduit pas du réseau** :
le jeton est rangé ici, ou il ne l'est pas — un tailnet coupé ne l'efface pas.

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

**LA CONCLUSION SE LIT SUR LA FRONTIÈRE, PAS SUR UN COMPTE.** C'était le second
défaut, et il tenait au premier : la conclusion comptait les étapes « à faire » et,
quand il n'y en avait aucune, annonçait « Vérification en cours… » — indéfiniment,
sans jamais nommer ce qui manquait. Elle nomme maintenant la première étape non
franchie quand elle est « à faire » (« Il reste une étape : « Cet appareil est
appairé » »), et ne compte que s'il y en a plusieurs. Quand c'est une étape
INCONNUE qui bloque, le doute l'emporte : on ne peut rien affirmer des suivantes.

**ON N'OUTILLE QUE CE QUI RESTE.** Une étape franchie n'affiche ni explication ni
commande : elles noieraient celle qui bloque. Et parmi les étapes non franchies,
seule la PREMIÈRE porte sa méthode dépliée : c'est la seule exécutable maintenant,
les autres supposent la précédente franchie. Leur marche à suivre existe toujours,
derrière « Méthode » — trois jeux de commandes à l'écran noyaient celle qui compte.

**DEUX RÈGLES DE VERROU, PARCE QUE LES DEUX LISTES NE DISENT PAS LA MÊME CHOSE.**
Sur un **diagnostic**, on juge une machine : la frontière est MESURÉE, et les cinq
étapes forment une chaîne — on n'installe pas le plugin avant d'avoir publié le
port, et on ne scanne pas le QR code d'un panneau qui n'existe pas encore. Sur une
**liste de travail** (la page d'ajout), le Mac n'a même pas encore d'adresse : ses
étapes sont une liste, pas un verdict, et **seules les étapes DU MÊME CÔTÉ se
précèdent**. Sans cette nuance, le seul geste que l'appareil a à faire ici —
prendre le QR code — restait grisé derrière un travail qui se fait ailleurs, sur
une machine que l'application ne connaît pas. Le verrou DIT d'ailleurs quel numéro
le bloque (`etapeQuiBloque`) : l'appairage n'étant précédé que par Tailscale,
écrire « après l'étape 4 » aurait renvoyé vers une étape déjà franchie.

**LE REPÈRE « SUR LE MAC » N'EXISTE QUE SUR LA LISTE DE TRAVAIL.** Sur la page
d'une machine, le titre dit déjà de laquelle il s'agit. Sur la page d'ajout, les
étapes du Mac et celles de l'appareil se mélangent sans qu'aucune machine soit
nommée — et c'est ainsi qu'on finit par taper une commande sur le mauvais
ordinateur. Le repère coûte deux mots, et il les vaut ; VoiceOver le lit aussi,
puisqu'un lecteur d'écran ne voit pas la couleur discrète qui distingue les deux.

**UNE EXPLICATION SUIT SON ÉTAT.** Les explications étaient écrites au présent de
l'étape FRANCHIE, et les deux copies de la liste — appareil hors tailnet, machine
jugée — les répétaient telles quelles. Sur un Mac éteint, la page lisait donc, sous
un titre déclarant l'étape « à faire » : « Il est en ligne sur le tailnet, donc la
découverte le propose ». Constaté sur capture, et signalé par le propriétaire :
« l'étape 2 si le serveur est off-line, le message doit le prendre en compte ». Une
explication qui contredit son propre état fait douter du diagnostic entier, et
envoie chercher au mauvais endroit.

Les textes vivent dans une **fabrique unique** (`EtapesServeur.etape(_:_:)`), que
les deux sorties de `etapes(...)` partagent — c'était la duplication qui avait
laissé la phrase fausse à deux endroits. Trois formes, une par état : pour une
étape **franchie**, ce que l'état EST ; pour une étape **à faire**, le constat
INVERSE, sans la marche à suivre (la méthode s'affiche juste en dessous, et
l'écrire deux fois dilue celle qui compte) ; pour une étape **inconnue**, ce que
l'étape DEMANDE, puisqu'on ne peut rien constater.

Vérifié par capture, sur les deux cas qui comptent : MacMini (port ouvert, plugin
absent → étapes 1 et 2 vertes, étape 3 à faire avec le bloc `cordis.patch.yml` à
copier) et un Mac hors ligne (étape 1 à faire avec `tailscale status` / `tailscale
up`, les suivantes « à vérifier »). Depuis la cinquième étape, une troisième
capture a été prise sur cette machine même (`--page-seule`) : les cinq constats
franchis, la conclusion « Ce serveur est prêt. », et les réglages repliés.

11 tests couvrent le calcul des états, dont les cas d'ignorance, la cinquième
étape et les deux règles de verrou.

#### Quand la machine répond mais n'a pas le plugin : le dire, et donner la démarche

Demande du propriétaire : « il faut dire dans remote que le plugin n'est pas installé et
donner la démarche ». Deux choses, donc — un CONSTAT nommé, et une PROCÉDURE.

Le cas mesuré sur MacMini : son port 80 est publié (la racine répond « dsh web authentication
required »), mais `/dsh-remote/v1/sante` rend **404**. Ce n'est ni le tailnet, ni
`tailscale serve`, ni le jeton : c'est le plugin qui n'y est pas chargé.

**LA DÉMARCHE EST DEVENUE UN PROMPT, ET ELLE A CHANGÉ DE NATURE.** Elle portait le bloc YAML
entier, recopié du README du plugin — deux copies d'une même vérité, dont celle-ci décrit une
ligne de configuration dont dépend tout le reste. La page affiche maintenant **une consigne
courte, à coller dans une session DSH du Mac** :

> Installe le plugin `dsh-remote` dans le profil web de ce harness : clone
> `https://github.com/VISIALIS/dsh-remote`, puis suis la section « Chargement » de
> `plugin/README.md` — c'est elle qui porte la ligne exacte à ajouter à
> `~/.dsh/profiles/web/cordis.patch.yml`. Ne redémarre pas le harness : le profil recharge
> ce patch à chaud. Vérifie ensuite que `curl … /dsh-remote/v1/sante` rend 401 ou 200, et
> dis-moi où se trouve la fonction d'appairage dans l'interface web.

Trois choses ont motivé ce changement, et chacune est un défaut de la version précédente :

1. **ELLE DEMANDAIT DE REDÉMARRER LE HARNESS, ET C'ÉTAIT FAUX** — sur son point décisif. Le
   profil est en `patchReload: live` : ajouter la ligne au patch est rechargé **à chaud**, et
   les routes apparaissent en quelques secondes. Ce n'était pas seulement écrit : c'est
   **mesuré depuis**, sur une instance vivante — `401` → `404` → `401` autour du retrait et de
   la remise de la ligne, **PID du harness inchangé** du début à la fin. Pour une PREMIÈRE
   installation, il n'existe d'ailleurs aucun « ancien processus qui continue de répondre » :
   l'argument était faux au moment où on le lisait.
   **LE BOUTON, LUI, DEMANDE UN RECHARGEMENT D'ONGLET — ET C'EST MESURÉ AUSSI.** La même
   expérience a montré qu'il disparaît tout seul quand la ligne est retirée, mais **ne revient
   pas** quand elle est remise : la page ouverte tient son graphe de modules du chargement, et
   un bundle ajouté après coup n'y entre pas. « Rechargez l'onglet » est donc une ÉTAPE de la
   procédure, pas une précaution de style — et le harness, lui, n'est jamais redémarré. Le
   détail est au README du plugin (tableau du § « Ce que `patchReload: live` recharge », et
   P12).
2. **ELLE ÉTAIT ÉCRITE SUR L'APPAREIL, POUR UNE MACHINE OÙ L'ON N'EST PAS.** C'est le Mac qui
   doit cloner, déclarer et vérifier. La consigne le dit maintenant en toutes lettres (« sur
   le Mac qui héberge DSH — pas sur cet appareil »), et c'est l'agent de ce Mac qui exécute :
   il lit la section du README **dans la version du dépôt qu'il vient de cloner**, donc à
   jour par construction.
3. **IL MANQUAIT L'INSTALLATION DE DSH ELLE-MÊME.** Une machine qui n'a jamais eu DSH ne rend
   pas de `404` : rien n'écoute, et c'est l'étape 3 qui s'affiche. Sa démarche commence donc
   désormais par la commande vérifiée à la source — la page officielle du harness, « Quick
   start : Install Node.js, then launch the Web UI with npx » :

   ```sh
   npx @deepseek-ai/dsh web
   ```

   Le README du paquet publié `@deepseek-ai/dsh` ne contient **aucune** section d'installation :
   c'est la page du harness qui fait foi, et c'est écrit ici pour que personne ne la cherche
   dans le paquet.

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

**ET ELLE CÈDE LA PLACE AU DIAGNOSTIC QUAND LA MACHINE CHOISIE N'EST PAS APPAIRÉE.**
Demande du propriétaire : « si je sélectionne un serveur, s'il n'est pas appairé, le
diagnostic s'affiche à la place de l'espace de travail ». C'est cohérent : sans
appairage il n'y a **aucun** espace à montrer — ni arbre, ni session —, et ce qu'il
faut lire est justement ce qui manque. Le diagnostic vient donc **à la place**, et les
deux sections sont exclusives : la conclusion d'abord (la barre n'a pas la bande
« verdict » de la fiche), puis les cinq constats et la méthode de celui qui bloque.
C'est **la même vue** que la deuxième bande de la fiche (`DiagnosticDuServeur`) : deux
dessins des mêmes constats auraient divergé. Sur iPhone, la barre latérale EST l'écran
principal — l'action utile y est donc à un appui, sans ouvrir la fiche.

**LA SECTION « ESPACES DE TRAVAIL » DISPARAÎT QUAND ELLE N'A RIEN À DIRE.** Demande du
propriétaire : « pour l'espace de travail, le fait qu'un serveur n'existe pas encore —
faire disparaître espace de travail s'il n'y a pas de serveur sélectionné ». Sur un
appareil neuf, elle affichait un titre, « 0 session », et une phrase renvoyant à une
machine inexistante, alors que le carrousel au-dessus dit déjà quoi faire.

La règle vit dans le modèle (`ModeleApp.aQuelqueChoseADireDUneMachine`), parce qu'elle a
un cas délicat : **ce n'est pas `serveurs.isEmpty`**. Une adresse SAISIE À LA MAIN
n'appartient à aucune liste — la machine n'est donc pas dans `serveurs` — et pourtant ses
espaces et ses sessions existent et s'affichent. Les cacher serait une régression, pas un
nettoyage. La question est donc « y a-t-il une machine à montrer, OU quelque chose qui
vienne d'une machine ? », et deux tests la tiennent (appareil neuf ; adresse saisie avec
des espaces).

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
portait l'unique bouton « Installer Tailscale ». Or la page qui donne les cinq étapes
n'était atteignable que par la vignette « Ajouter » du carrousel… **qui ne s'affiche pas
quand la liste est vide** : l'appareil qui a le plus besoin des cinq étapes — celui qui
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

##### La fiche est structurée en quatre bandes — et c'est la MÊME pour les deux pages

Deux constats du propriétaire, à un mois d'intervalle, et le second a commandé la refonte :

> « la page détail des serveurs est moche, tu peux faire quelque chose ? À commencer par
> mieux structurer. »

> « Je souhaite revoir la page détail des serveurs qui est trop lourde et qui a l'historique
> dépassé du projet. C'est surtout la partie diagnostic qui me pose problème. Cette page
> n'est pas assez standardisée : ajouter un serveur devrait garder le même patron. »

Le premier constat était **structurel**, pas esthétique : six blocs de même poids s'empilaient
dans l'ordre où le code avait grandi — en-tête, adresse, jeton, interrupteurs, bandeau
d'erreur, diagnostic —, si bien que le DIAGNOSTIC, raison d'être de la page, se lisait en
dernier. Le second a montré ce qui restait : **deux mises en page pour un seul contenu** —
`VueServeur` empilait identité, diagnostic, réglages et détail technique, `VueAjoutServeur`
enchaînait un en-tête, les étapes de l'appareil, deux actions et un bloc replié pour le Mac —
et **deux jeux de méthodes** qui avaient déjà divergé sur les deux premières étapes.

Il n'y a plus qu'une vue, `FicheServeur`, et `serveur == nil` y veut dire « Ajouter un
serveur ». L'ordre suit les questions qu'on se pose, et rien d'autre :

| Bande | Contenu | Ce qu'elle règle |
|---|---|---|
| 1. Verdict | pastille, **la conclusion en une phrase**, adresse copiable, **une** action (ou, en mode ajout, la phrase qui sépare les deux mondes et les deux recours) | l'état se dit une fois, et l'action proposée peut aboutir |
| 2. Parcours | les **cinq** constats, sans titre | la démonstration, avec **une seule** méthode dépliée : celle de l'étape qui bloque — ou, sur une liste de travail, celle de **cet appareil** |
| 3. Réglages de cette machine | jeton d'appoint, suivi, filtre — **repliés** | chaque réglage reste à l'endroit qui le rend vrai, sans s'interposer entre l'adresse et le verdict |
| 4. Détail technique | l'erreur brute — **repliée**, et seulement si rien ne l'explique | une phrase en français n'est pas un détail technique |

**LES BANDES 3 ET 4 N'EXISTENT PAS EN MODE AJOUT** : il n'y a pas encore de machine dont on
puisse régler le jeton ni lire l'erreur. Et **la conclusion a quitté la bande 2 pour la
bande 1** : elle était sous un titre « Diagnostic », ce qui obligeait à lire quatre constats
pour apprendre ce que la page avait à dire.

**CE QUI A ÉTÉ RETIRÉ, ET POURQUOI.** Trois choses, toutes mesurées à l'écran ou dans le
code : le titre « Diagnostic » (la conclusion est juste au-dessus, et la première ligne
s'annonce elle-même) ; le paragraphe du jeton expliquant qu'il ne s'affiche qu'une fois —
c'est vrai, mais le chemin normal est devenu l'appairage, et le champ n'est plus qu'une
porte de service ; et la marche à suivre dupliquée dans les deux pages, qui n'existe plus
qu'une fois (voir plus bas).

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

**VÉRIFIÉ DEPUIS, ET LA REMARQUE QUI SUIVAIT ÉTAIT FAUSSE.** Ce paragraphe disait la
modification « non vérifiée à l'écran » parce que `screencapture` exige l'autorisation
« Enregistrement de l'écran », « refusée dans cet environnement ». Elle ne l'est pas :
le 14 septembre 2026, deux captures macOS ont été prises sans intervention
(`--page-seule`, `--page-seule --ajout`), et elles ont servi à juger la refonte de la
fiche. La modification emploie l'API de ligne documentée (`listRowSeparator`),
appliquée à chaque ligne et non au conteneur — posée sur un conteneur, elle serait sans
effet, ce qui est pire qu'un séparateur.

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

**Mesure du 13 septembre, Xcode 26.6 — elle corrige une note antérieure.** La phase
fonctionne : DerivedData neuf, `App/Info.plist` source propre, l'exception est
**présente** dans le paquet produit, en Debug **et** en Release simulateur. Sans
`Config/DomaineTailnet` — le cas d'un clone —, le paquet se construit **sans** exception
et **sans erreur**, ce qui est le piège décrit plus haut. Une mesure antérieure (Xcode
26.2, quatre paquets : Debug/Release × simulateur/appareil) donnait zéro exception, et
c'est elle qui a fait écrire `Scripts/construire-app-ios.sh` ; la configuration
« appareil » n'a pas été remesurée. Ce script reste le chemin le plus sûr — il écrit
l'exception dans l'`Info.plist` que Xcode lit, donc rien ne peut la réécrire après coup —
et l'écran d'adresse annonce désormais le refus `-1022` **avant** l'essai
(`ConseilAdresse`), au lieu de laisser l'utilisateur chercher une panne réseau.

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

La liste se rafraîchit **toutes les 3 secondes** tant que quelque chose bouge, et
**toutes les 15 secondes** quand rien ne tourne — et l'interrupteur « Suivre
l'activité » permet de l'arrêter complètement.

Sans ce suivi, les pastilles ne changeaient qu'au lancement ou par glissement :
le propriétaire a vu « des points bleus partout » alors que le serveur signalait
déjà deux sessions en cours. **Un indicateur d'activité qui ne s'actualise pas
est pire qu'aucun indicateur** : il donne une image fausse avec l'autorité d'une
mesure.

**La cadence n'est plus fixe, et c'est une question de radio.** Trois secondes
était la bonne réponse à « qu'est-ce qui tourne ? » — pas une raison pour la
poser en boucle quand rien ne tourne et que personne ne regarde : sur un iPhone,
chaque tour réveille la radio. La règle (`ModeleApp.cadence`, une fonction PURE,
donc éprouvée seule) est : **rapide** si une session est `en_cours`, si une
décision est attendue, ou si un flux est ouvert — c'est-à-dire si l'utilisateur
vient d'envoyer un prompt ; **lente** sinon. Le repos reste à quinze secondes, et
pas trente : au-delà, la liste cesserait d'être un tableau de bord pour devenir
une photo ancienne — un tour lancé depuis un autre appareil doit apparaître.

### L'arrière-plan : ce qui s'arrête, ce qui est REPRIS

**Le défaut.** Trois boucles et une socket « tournaient » pendant qu'iOS gèle le
processus, et la temporisation de reconnexion reprenait au réveil avec un quota
entamé : le cas « l'application a dormi dix minutes et le flux affiche un échec ».
`isIdleTimerDisabled` ne couvre que l'écran allumé, et rien n'accrochait
`scenePhase` au modèle.

**Ce qui est fait, à chaque phase** (`VuePrincipale` lit `scenePhase` parce que
c'est elle qui tient le modèle) :

| Phase | Ce qui se passe | Pourquoi |
|---|---|---|
| `.background` | boucles arrêtées, flux fermé, reconnexion en vol annulée | libérer la radio et ne pas brûler le quota pendant que le processus est gelé |
| `.active` | quota de reconnexion **remis à neuf**, relecture **immédiate**, flux rouvert avec `depuisSeq` | l'utilisateur qui rouvre doit voir l'état de maintenant, sans doublon et sans perte |
| `.inactive` | **rien** | iOS passe par cet état pour le sélecteur d'applications, une bannière ou le centre de contrôle : y couper le flux le romprait à chaque notification |

**`enDirect` survit à l'arrière-plan**, et c'est délibéré : c'est l'INTENTION de
l'utilisateur — « je suivais cette session » — et c'est elle qui décide de la
réouverture. L'éteindre ferait disparaître le direct au retour, sans que personne
ne l'ait demandé. Le quota, lui, n'est remis à neuf que s'il y a un flux à
rouvrir : un compteur de reconnexion sans flux afficherait « Reconnexion… » dans
la barre d'outils pour un suivi qui n'existe pas.

**Éprouvé sur le modèle complet** (`CycleDeVieTests`, client factice) : après
suspension, **aucun listage ne part** pendant quatre secondes alors que la
cadence rapide est de trois — et la vérification inverse a été faite, l'assertion
échoue si `arreterSuivi()` disparaît (`attendu 2, vu 3`). Au retour : un listage
part **immédiatement**, et le quota repasse à zéro après avoir consommé un essai
sur un flux réellement mort.

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

**Où est ce champ, et pourquoi c'était un cul-de-sac.** Une revue d'interface a montré
que le champ n'existait que sur la page d'une machine **connue** — or cette page s'ouvre
après une découverte, qui exige une connexion authentifiée. Sur un iPhone neuf : liste
vide, donc aucune page de machine, donc aucun champ ; la connexion ne pouvait finir qu'en
`401`, et le message du `401` renvoyait vers les **Réglages**, qui ne contiennent plus
aucun champ de jeton depuis que chaque hôte a le sien. Le remède prescrit était un écran
vide, et le champ réel était derrière une porte fermée.

Le jeton est donc **aussi** dans la feuille « Adresse » — le seul écran qu'un appareil
neuf puisse ouvrir —, dans une section qui lui est propre :

| Où | Quand |
|---|---|
| Feuille « Adresse » | saisie manuelle d'une adresse, donc sur un appareil neuf |
| Page d'une machine | la machine est déjà dans la liste : c'est son jeton, et lui seul |

**Le champ d'une page est celui de la machine AFFICHÉE.** Une page de serveur peut
s'ouvrir sur un hôte auquel on n'est **pas** connecté — c'est même le cas qui donne
son sens au remède d'installation. Or la lecture, l'écriture et l'effacement
passaient tous par la cible : le champ annonçait « Jeton d'appareil de cet hôte »
et affichait le jeton d'une autre machine, pouvait envoyer vers la cible un jeton
collé sur la fiche d'un autre, et effaçait le jeton de la cible depuis la page d'une
autre. Tout passe désormais par l'adresse de la page, et `jetonSaisi` — la valeur la
plus fraîche, mais qui ne décrit **que** la cible — n'est plus lu pour une autre
machine. Le rappel du `401` ne s'affiche que sur la page de la machine visée : un
`401` parle de la connexion en cours, pas d'une fiche qu'on consulte.

Deux détails d'implémentation, et le second est une règle de sécurité :

- le champ de la feuille est **local** (`@State`) et n'est engagé qu'à l'appui sur
  « Se connecter » ou « Tester l'adresse ». Une liaison directe au modèle aurait confié
  au trousseau, caractère par caractère, un jeton tronqué rangé sous une **adresse
  tronquée** — autant de copies partielles d'un secret que de préfixes d'adresse ;
- l'adresse change de machine à chaque frappe : le champ se recale alors sur le jeton de
  l'adresse affichée, pour qu'un secret saisi pour l'une ne puisse pas être engagé pour
  l'autre. La règle « chaque hôte a le sien » tient donc aussi ici.

Le message du `401` nomme maintenant les deux endroits qui portent réellement le champ,
et un test l'empêche de reconduire un renvoi vers un écran qui n'en a plus.

**Prérequis côté appareil**, indépendants du code : brancher l'iPhone en USB (ou activer
la synchronisation Wi-Fi), l'appairer et faire confiance à cet ordinateur, puis activer
**Réglages ▸ Confidentialité et sécurité ▸ Mode développeur** sur l'iPhone. Tant que
`xcrun devicectl list devices` donne `No devices found`, aucune installation n'est
possible — c'est un préalable matériel, pas logiciel.

### L'appairage par QR : un geste remplace la recopie

**Ce que ça remplace.** Jusqu'ici, rattacher un appareil demandait deux saisies sur
deux écrans : l'adresse, puis 43 caractères recopiés d'un terminal où ils ne
s'affichent **qu'une fois** — une faute de frappe coûtait une rotation de jeton. Le
panneau « Appairer un appareil » de l'interface web du Mac (voir le plugin
[`dsh-remote`](../../plugins/dsh-remote/)) affiche un QR code **et** son texte ; les
deux portent l'adresse et un **code à usage unique de deux minutes**.

| Appareil | Le geste | Pourquoi celui-là |
|---|---|---|
| iPhone, iPad | **Scanner le QR code** (`VueScan.swift`, `DataScannerViewController`) | un Mac ne peut pas scanner son propre écran |
| Mac | **Coller un appairage** — le texte affiché sous le QR | idem, et le presse-papiers est le canal le plus court |

**APRÈS LE SCAN, LA PAGE D'AJOUT S'EFFACE — correction signalée à l'usage : « quand je
scanne le QR code, il faudrait que la page s'actualise ».** L'appairage réussissait de
bout en bout — jeton rangé, connexion faite, sessions chargées — mais la page d'ajout
restait à l'écran : son travail est terminé dès qu'une machine est appairée, et rien ne
la quittait. Elle part maintenant par deux chemins, parce que les plateformes ne la
présentent pas de la même façon : sur iPhone elle est **poussée**, et `dismiss` la
dépile ; sur macOS et iPad elle occupe la **colonne de détail**, où c'est l'état de
l'application qui décide de ce qu'on regarde (`surAppairage` → `ajoutOuvert = false`).
Sur la fiche d'une machine DÉJÀ ouverte, en revanche, rien ne se ferme : le verdict
change et les cinq constats passent au vert tout seuls, puisque le modèle est observé.

**OÙ LE GESTE SE TROUVE — ET POURQUOI IL A FALLU LE DÉPLACER.** Le premier jet
l'avait mis dans la feuille « Adresse », en première section, avec ce raisonnement :
« un appareil neuf n'ouvre que cette feuille ». Il était **faux**, et l'usage l'a dit
en une phrase : *« sur l'iPhone, je n'ai pas de système avec un QR code »*. Un appareil
DÉJÀ configuré — le cas de tous les jours — n'a aucune raison d'ouvrir la feuille
« Adresse », dont le bouton promet d'ailleurs « Saisir une adresse ». Le geste vit
donc maintenant **là où l'on ajoute un serveur** :

| Écran | Ce qu'on y voit |
|---|---|
| « Ajouter un serveur » (`--ajout`) | **Scanner le QR code** (iOS) / **Coller un appairage** (macOS), en bouton plein, juste sous la seule étape qui concerne l'appareil |
| Aucun serveur joignable | le même bouton, en premier |
| Feuille « Adresse » | la section reste — c'est le chemin d'un appareil vierge, il n'est pas perdu |
| Feuille « Appairer un appareil » | le scan, le collage, **et un champ pour renseigner le texte du QR code** (presse-papiers occupé ailleurs, code reçu par message, caméra refusée) |

Les libellés **nomment le QR code**, parce que c'est le mot qu'on cherche.

**LA PAGE « AJOUTER UN SERVEUR » NE PARLE PLUS QUE DE L'APPAREIL —** et c'est une
seconde correction, demandée après usage : « les différentes étapes devraient être
focus uniquement sur le fait que Tailscale est configuré, et ensuite la possibilité
de prendre un QR code ; toutes les autres étapes sont dépendantes du plugin sur le
harness ». C'était juste — et elles sont désormais DEUX : Tailscale, et l'appairage,
qui se constate dans le trousseau. Les trois autres se **constatent** depuis
l'appareil, et l'application **vérifie déjà** les trois autres (le diagnostic « Ce
serveur est prêt », sur la page de la machine). Les enseigner au même niveau
faisait apprendre au remote un travail qui n'est pas le sien. Le modèle porte
désormais la distinction (`EtapesServeur.Responsable`) et la page en découle :

1. **cet appareil** : « Tailscale est connecté sur cet appareil », et le geste ;
2. **le Mac** : les trois autres étapes, **repliées** sous « Si le Mac n'est pas
   encore prêt » — elles restent écrites, parce qu'on est souvent devant le Mac
   quand on cherche pourquoi rien ne répond, mais elles ne sont plus un préalable. La saisie manuelle reste en dessous, pour le cas où le Mac n'est pas à portée.
Le collage iOS passe par `PasteButton`, donc **sans bannière** : c'est le système qui
accorde l'accès, pas nous qui lisons le presse-papiers à l'insu de l'utilisateur.

**L'APPLICATION ÉCHANGE, ELLE NE RANGE PAS LE CODE.** Un code de 22 caractères rangé
dans le champ du jeton serait envoyé comme jeton porteur, et rendrait un `401` qui
ferait chercher une panne d'authentification là où il manque un échange. Le modèle
distingue donc les deux genres : un **jeton** se pose tel quel (c'est celui du
terminal), un **code** part à `POST /dsh-remote/v1/appairage/echange` — avec le nom
de l'appareil, sans lequel la liste des appareils n'aurait que des empreintes — et
c'est le jeton **reçu** qui va au trousseau, par hôte. Si l'échange échoue, **rien**
n'est rangé : ni l'adresse, ni le jeton, ni le trousseau.

**Trois refus, trois messages.** Le protocole a maintenant trois `403` : origine
refusée (une erreur de client), écriture refusée (une portée insuffisante), et
échange refusé — « code expiré » ou « code déjà utilisé ». Les confondre afficherait
« un client natif ne doit jamais envoyer d'en-tête Origin » à quelqu'un dont le code
a simplement expiré. Les deux motifs connus sont **traduits** (l'hôte écrit en ASCII
sans accent, parce que ses messages finissent dans un journal de terminal) ; un motif
inconnu est affiché tel quel plutôt qu'inventé. Et un `404` sur l'échange dit « cet
hôte ne sait pas échanger un code : son plugin est plus ancien » — un remède
différent.

**La caméra est déclarée, et elle ne sert qu'à ça.** `NSCameraUsageDescription` est
dans `App/Info.plist` : sans cette clé, iOS **termine** l'application à l'ouverture du
scanner — un plantage, pas un refus, et il ne se voit qu'à l'usage. Aucune image n'est
enregistrée, analysée ni transmise : seul le **texte** lu est analysé, par
`Appairage.analyser`. **Limite assumée** : cette phrase est en français seulement, la
traduire demanderait un `InfoPlist.strings` qui n'existe pas encore.

**Sur simulateur, il n'y a pas de caméra**, et l'application le dit au lieu d'afficher
un écran noir : la vue annonce « Caméra indisponible » et renvoie au collage, qui fait
exactement la même chose.

**Le contrat est partagé avec l'hôte**, et c'est ce qui rend le geste sûr : la charge
utile (`dshremote://<hôte>/<genre>/v1/<secret>`) est construite en JavaScript et
analysée ici, et **le même fixture** est rejoué des deux côtés
(`Fixtures/vecteurs-appairage.json`, `AppairageTests.swift` d'un côté,
`plugins/dsh-remote/tests/appairage.test.js` de l'autre). Une divergence casse un test
avant d'atteindre un appareil.

**Où l'on révoque un appareil** : dans le panneau du Mac, section « Appareils
appairés » — jamais depuis l'application, qui n'a pas de route pour cela (un porteur
de jeton ne doit pas pouvoir expulser les autres). C'est là aussi que la portée
accordée est annoncée **avant** le scan (« l'appareil recevra un jeton qui LIT sans
écrire »).

**Ce qui est éprouvé, et ce qui ne l'est pas encore** (RÈGLE #5). Éprouvé sans
appareil : l'analyse (9 tests, fixture partagé), l'application au modèle et l'échange
(10 tests : code échangé avec l'adresse et un nom, jeton reçu rangé par hôte, refus
qui ne change rien), les trois `403` et le `404` (6 tests), la parité des tables de
traduction, les constructions **macOS** et **iOS simulateur**, et la construction
**iOS appareil** (Release, `generic/platform=iOS`).

**LE SCAN CAMÉRA EST ÉPROUVÉ, ET IL A FALLU UN VRAI APPAREIL.** Constaté par le
propriétaire sur son iPhone, le 14 septembre 2026, avec le paquet `Release` installé
par `devicectl` : le QR code du panneau est lu, l'échange se fait, la machine
apparaît. Deux défauts ont été trouvés par ce même essai, et corrigés — la page
d'ajout qui restait à l'écran après l'appairage, et la fiche qui survivait à une
réinitialisation. **Reste non éprouvé** : le collage bout en bout depuis le Mac
(l'échange est éprouvé par les tests, le geste ne l'est pas), et le fait que le
bouton du panneau revienne **sans** recharger l'onglet — la mesure a montré qu'il ne
revient pas (voir P12 au README du plugin).

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

**Le brouillon appartient à SA session.** Le texte en cours était un champ unique :
écrire dans une session, changer de session, et le texte suivait — il pouvait donc
partir vers une autre. Les brouillons sont rangés par couple hôte/session, comme
les jetons. Revenir à une session retrouve son texte ; changer d'hôte n'en hérite
pas. Conséquence pour le bouton d'envoi : « vide » veut dire « rien qui puisse
partir », pas « zéro caractère ».

**L'acquittement ne détruit plus la frappe concurrente.** Le champ reste modifiable
pendant l'envoi, et l'acquittement faisait `brouillon = ""` après l'attente réseau :
ce que l'utilisateur écrivait pendant que son message partait était perdu. Ce qui
est retiré est maintenant ce qui est **parti** — le champ est vidé s'il contient
encore exactement le texte envoyé, le préfixe envoyé disparaît si la frappe a
continué, et **rien** n'est touché si le texte a divergé. Deviner quoi garder
reviendrait à effacer un texte que personne n'a envoyé.

L'acquittement et le refus sont rangés **avec** leur session : un envoi acquitté
après un changement de session ne s'affiche plus sous une session qui n'a rien
envoyé. Et changer de session n'efface plus le texte — seulement les messages.

Le mode d'envoi est écrit en clair — **« À la suite »** ou **« Tout de suite
(interrompt) »** — plutôt que caché derrière une icône : la différence entre tenir
la file et s'insérer dans un tour en cours ne se devine pas.

**Interrompre un tour se confirme.** Le glyphe rouge était collé au bouton d'envoi,
à huit points : viser l'un et toucher l'autre arrêtait un travail en cours. Un trait
les sépare, et la boîte de confirmation dit ce qui est conservé — le travail déjà
fait et la file d'attente.

L'annulation **conserve la file d'attente** : ce qui n'a pas encore été traité
reste en attente. Une session froide est refusée (`404`) — il n'y a rien à
interrompre.

### Les alertes : « l'agent attend », « c'est fini »

C'est la seule information que l'application ne savait pas dire **quand on ne la
regarde pas**. La section « Demande votre attention » la remonte en tête de liste —
mais il faut ouvrir l'application pour la voir, et les six réviseurs de l'audit en
ont fait la valeur d'usage n° 1.

**Éteintes par défaut, et l'autorisation n'est demandée qu'au moment où on les
allume.** Une application qui réclame le droit d'envoyer des notifications au
lancement apprend à être refusée. L'interrupteur vit dans les réglages, à côté de ce
qu'il concerne, et il **suit l'état réellement obtenu** : un refus du système le
laisse éteint plutôt que d'afficher un « oui » qui ne produirait rien.

**Ce qui déclenche une alerte, et ce qui la tait** — la décision est une fonction
pure (`Alerte.aEnvoyer`), donc elle se relit :

| Règle | Pourquoi |
|---|---|
| Une attente **nouvelle** | La liste est rafraîchie toutes les trois secondes : alerter sur l'ÉTAT enverrait vingt notifications par minute |
| Une fin de tour **nouvelle** | Même raison ; le rappel de fin existait déjà à l'écran |
| **Rien pour ce qu'on regarde** | Même règle que le rappel de fin : une notification pour un écran qu'on a sous les yeux est du bruit |
| **Une** alerte par événement, avec le compte | Cinq sessions qui se terminent ensemble font une alerte « 3 tours… », pas cinq — une pile de notifications identiques s'apprend à être ignorée |
| Rien à la **première** liste, ni après un changement de machine | Au lancement, tout est « nouveau » : alerter ferait sonner l'application pour un état que l'utilisateur voit à l'écran. La comparaison retient donc la GÉNÉRATION de la cible |
| L'attente **avant** la fin | L'attente demande une action ; une fin est une bonne nouvelle à lire |

**La limite, écrite là où on allume les alertes et pas seulement ici.** Une alerte
locale part d'un processus **vivant** : iOS suspend une application quelques secondes
après son passage en arrière-plan, et rien ne peut alors être observé. Ce qui est
couvert est donc « l'agent a fini pendant que je regardais ailleurs », pas
« prévenez-moi cette nuit ». La réveiller demanderait un serveur de notification —
ce projet n'en a pas, et n'en veut pas (RÈGLE #0 : aucune donnée ne sort de la
machine).

**Une garde mesurée, pas une précaution.** `UNUserNotificationCenter.current()` exige
un identifiant de paquet, et un binaire nu ne rend pas `nil` : il **lève** et le
processus **avorte** (mesuré : `NSInternalInconsistencyException:
bundleProxyForCurrentProcess is nil`, code 134, signal 6). Sans la garde, `swift run
DSHRemoteMac` — le chemin de développement documenté — mourrait au lancement.

### La langue de l'interface : le français reste la source, l'anglais est ajouté

**La décision** : le code, les commentaires, les clés et la documentation restent en
français (RÈGLE #1) ; l'interface se traduit. Les tables vivent dans la
bibliothèque, avec le français pour langue de référence.

**Ce qui est traduit aujourd'hui, et ce qui ne l'est pas encore** — l'état exact,
parce qu'une application à moitié traduite qui se dit bilingue serait une promesse
non tenue :

| Élément | État |
|---|---|
| Les **phrases de l'interface** (titres, boutons, libellés, infobulles, libellés VoiceOver) | **traduites** |
| Les **messages construits par le modèle** — états d'une machine (« hors ligne », « à appairer », « jeton refusé »), constats du diagnostic en cinq étapes, refus d'écriture, alertes | **traduits** : **206 clés** au total, et la parité des deux tables est tenue par un test — plus un contrôle dans `scripts/verifier.sh`, qui relit le CODE pour attraper une clé absente des DEUX tables |
| Les **langues de l'application** sont déclarées (`CFBundleDevelopmentRegion = fr`, `CFBundleLocalizations = [fr, en]`) | **fait**, sur les deux plateformes |
| Les phrases **interpolées** avec un nombre | **restent en français**, et il n'en reste que quatre : `« N évts »`, les deux titres d'alerte (`« N sessions attendent votre réponse »`) et les âges abrégés — le pluriel demande un traitement à part. Les phrases du DIAGNOSTIC, elles, ne sont plus dans ce cas : elles sont composées de morceaux traduits, seuls les nombres étant interpolés (`EtapesServeur.resume`), et un test les compare désormais dans la langue de l'application |
| L'**aide sous le champ d'adresse** (`ConseilAdresse`) | **reste en français** : ses deux avertissements ATS sont des littéraux multi-lignes, que le générateur — qui relit le code LIGNE À LIGNE — ne sait pas encore voir |
| Les **âges abrégés** (« 5min », « 3h », « 2mois ») et les messages **venus de l'hôte** (motifs de refus du plugin) | **restent en français** — les uns sont des abréviations, les autres appartiennent au protocole |

**Trois choses mesurées en chemin, et qui expliquent la forme du code.**

1. **Un littéral passé à `Text` cherche dans le programme PRINCIPAL**, où les tables
   de la bibliothèque ne sont pas : l'interface restait en français même lancée en
   anglais. C'est pourquoi les appels nomment le paquet (`bundle: .module`), par
   les deux fonctions `T` (texte) et `L` (chaîne) — `Button`, `Toggle` et `Section`
   n'offrant pas d'initialiseur qui accepte à la fois un `Text` et un paquet.
2. **SwiftPM recopie un catalogue `.xcstrings` sans le compiler** : le paquet de
   ressources ne contenait alors aucun `.lproj`, et rien n'était traduit. Les tables
   sont donc des `.lproj/Localizable.strings`, que SwiftPM **et** Xcode copient tels
   quels.
3. **Sans langues déclarées, l'application n'annonce rien** — et le binaire nu
   (`swift run DSHRemoteMac`) reçoit alors l'anglais par défaut, mesuré. Les deux
   `Info.plist` déclarent donc `fr` et `en` : sur l'application empaquetée, un
   système français affiche le français, et un système anglais l'anglais.

Le générateur est versionné — `Scripts/traduire.py` — et **relit les clés dans les
sources** : il refuse de produire une table anglaise incomplète. La parité n'est donc
pas seulement vérifiée à l'exécution par un test, elle est exigée à l'écriture.

**UNE LEÇON QUE LA SUITE DE TESTS A PAYÉE.** Traduire a fait échouer **dix-huit
assertions** d'un coup, dans quatre fichiers : elles comparaient l'affichage à des
phrases françaises **recopiées** — or le processus de test, comme le binaire nu,
n'annonce aucune langue et tourne donc en anglais. Les assertions comparent
maintenant à la **même fonction que l'application** (`L(« phrase »)`) : elles
vérifient le SENS d'un message sans dépendre de la langue dans laquelle il
s'affiche, et une phrase qui cesserait d'être traduite les ferait échouer.

### L'iPad : une cible réelle, et ce qu'elle a révélé

**La décision.** L'application ne se déclarait que pour iPhone (`TARGETED_DEVICE_FAMILY = 1`) :
sur un iPad, elle tournait donc en **mode compatibilité**, une fenêtre d'iPhone agrandie.
Elle déclare maintenant les deux familles, avec les **quatre orientations** propres à
l'iPad — `UISupportedInterfaceOrientations~ipad` est une clé distincte, et un iPad qui ne
déclarerait pas le portrait inversé se retrouverait la fenêtre à l'envers selon la façon
dont on le tient.

**Ce qui a été éprouvé, sur un iPad (A16) en simulateur** — 18 simulateurs iPad sont
installés sur cette machine :

| Constat | Preuve |
|---|---|
| Le paquet produit déclare bien les deux familles | `UIDeviceFamily = [1, 2]` et les quatre orientations dans l'`Info.plist` **construit** |
| L'application s'installe et se lance sur iPad | capture : **deux colonnes**, le carrousel de machines, « Demande votre attention », les espaces de travail avec leurs comptes, la recherche en bas, et « Aucune session ouverte » dans le détail |
| Elle joint le harness depuis le simulateur | « 1 joignable », carrousel alimenté — via `127.0.0.1:3080`, que le simulateur partage avec le Mac (cf. « Essai sur le simulateur iOS ») |
| Les orientations ne cassent rien | capture après rotation en paysage : la même mise en page, la colonne latérale en plus large |

**Un défaut trouvé en regardant, et corrigé.** La contrainte de largeur de la colonne
latérale (`navigationSplitViewColumnWidth`) ne vivait que dans la branche **macOS** : sur
iPad, la colonne prenait la largeur par défaut du système, et le contenu y était à
l'étroit — titre de section replié sur deux lignes, carrousel coupé au troisième chicon,
champ de recherche tronqué. La contrainte vaut maintenant pour les deux plateformes, à
**340 points minimum** (320 sur macOS, choisis pour d'autres raisons : voir le commentaire
du code). Sur iPhone, SwiftUI l'ignore : la colonne est l'écran entier.

**La connexion est atteignable sans le geste — et c'est une correction d'accessibilité.**
Sur iPhone, la vignette d'une machine est un `NavigationLink` doublé d'un geste
parallèle : c'est le **geste** qui connecte. VoiceOver, un clavier externe, Voice
Control ou un interrupteur activent le **lien** — ils ouvraient donc la page d'une
machine **sans s'y connecter**. La vignette porte maintenant une **action nommée
« Se connecter »**, atteignable par ces mêmes moyens, et une infobulle qui dit ce
que l'activation simple fait vraiment (« Ouvre la page de cette machine »).

Ce n'est pas la refonte que l'audit proposait (une sélection unifiée) : c'est le
chemin canonique de l'accessibilité, il couvre le défaut, et il ne touche pas au
câblage de la navigation — dont le remplacement demanderait d'être éprouvé au
doigt, ce que cet environnement ne permet pas. Sur macOS, rien à ajouter : la
vignette y est un `Button` qui connecte déjà.

**Ce qui n'est PAS éprouvé, et qui est écrit comme tel :**

- **le multitâche** (Split View, Slide Over, Stage Manager) : rien ne l'empêche —
  `UIApplicationSupportsMultipleScenes` reste `false`, donc l'application est une fenêtre
  unique, ce qui est le cas normal d'un client —, mais aucun essai n'a été fait ;
- **un iPad réel** : la signature demande un compte développeur, absent de cette machine
  (cf. « Installer sur l'iPhone : ce qui bloque, mesuré ») ;
- **le clavier et le pointeur** sur iPad, que la HIG attend d'une application iPad.

### Les blocs de code du journal

**Ce qui manquait.** Le journal affichait le texte de l'agent en brut, coupé à quatre
lignes. Mesuré sur 40 journaux réels de ce dépôt (52 669 événements, 9 491 messages
d'assistant) : **8,2 % des messages portent un bloc délimité par trois accents graves**
— et une sortie de `bash` ou un diff tronqué à quatre lignes de texte proportionnel ne
se lit pas.

**Ce qui est rendu, et ce qui ne l'est pas — une décision, pas un oubli.**

| Rendu | Ce qui est traité |
|---|---|
| Cadre monospace, fond distinct, **bouton copier**, replié à 12 lignes | les blocs délimités par trois accents graves, avec ou sans langage annoncé |
| Texte ordinaire, comme avant | **tout le reste** : titres, listes, gras, tableaux, liens. Un analyseur Markdown complet est un chantier de plusieurs jours, la RÈGLE #0 interdit d'en importer un, et le vrai lecteur d'un long document reste l'interface web |

Le bouton « Développer » de l'événement déplie **le texte et les blocs d'un coup** : deux
dépliages séparés se contrediraient.

**Un piège de Swift, mesuré en écrivant l'analyseur.** « `\r\n` » est **un seul
`Character`** (un groupe de graphèmes) : `split(separator: "\n")` ne le reconnaît pas et
rend une ligne unique. Un texte venu d'une machine Windows ressortait donc en **un seul
segment**, clôtures comprises, sans qu'aucun bloc ne soit vu. Le test qui l'a attrapé est
gardé, et la normalisation est faite avant de découper.

**Une ancre de vérification de plus : `--session=<fragment>`.** Le rendu d'un événement ne
se juge pas sur du code compilé, et cet environnement n'injecte pas d'appui dans une
liste. L'ancre ouvre le journal de la première session dont le titre ou le projet contient
le fragment. **Elle se rejoue quand la liste arrive** : la première tentative tombe juste
après `demarrer()`, qui rend la main sur la poignée de main — la liste suit, et l'ancre ne
trouvait rien. Constaté deux fois : la capture montrait la session *restaurée* au lieu de
celle demandée, ce qui rendait l'ancre trompeuse, donc pire que pas d'ancre du tout.

### Quand l'hôte n'écrit pas : le composeur absent SE DIT

Le composeur n'apparaît que si l'hôte annonce `capacites.ecriture` — la règle du
dépôt : « un bouton sans effet est un mensonge d'interface ». Mais il disparaissait
**en silence** : l'écran semblait complet, et rien n'indiquait que répondre était
impossible, ni pourquoi.

Depuis la portée du jeton côté plugin, il y a **deux causes** possibles, et leurs
remèdes ne sont pas au même endroit :

| Ce que l'hôte annonce | Ce que l'écran dit | Où est le remède |
|---|---|---|
| `portee: "lecture"` | « Ce jeton lit sans écrire : … `DSH_REMOTE_PORTEE=ecriture` » | **sur la machine** qui héberge le harness |
| pas de `portee`, ou `ecriture: false` | « Cet hôte n'annonce pas l'écriture : cette composition ne monte pas le service… » | dans la composition de l'hôte |
| rien n'est joint | rien — il n'y a rien à expliquer encore | — |

**`portee` est optionnelle, et `nil` ne veut pas dire « lecture seule »** : un hôte
antérieur à la portée ne la publie pas, et l'écran ne l'invente pas. C'est la même
discipline que partout ailleurs dans ce client — « je ne sais pas » n'est jamais
rendu comme « non ».

Et un `403` ne suffit pas à conclure : le même code sert à « origine refusée ». Le
corps porte la raison, l'application la lit, et les deux moitiés ont un test sur la
chaîne exacte. Sans cela, un jeton en lecture seule se serait affiché comme une
requête suspecte — un message faux, donc un remède faux.

### Le journal dit la vérité sur sa session

Trois défauts, tous visibles à l'écran et aucun à la compilation :

| Défaut | Ce qui a changé |
|---|---|
| Une lecture **échouée** laissait l'ancien journal sous le titre de la nouvelle session | le journal vide d'abord, puis se remplit : on lit, on a lu, on a échoué — trois états distincts. `journalPour` porte la session, `appliquerJournal` refuse tout ce qui ne la désigne pas (une réponse en retard ne peut plus s'appliquer), et la vue filtre ce qu'elle affiche |
| L'échec était **invisible** — le voile de chargement était conditionné à `journal.isEmpty`, donc jamais montré quand un ancien journal traînait | l'échec est nommé POUR CETTE SESSION (la connexion peut aller bien : c'est la lecture de CE journal qui a échoué), avec sa cause et un bouton « Réessayer » |
| Le journal ne **suivait pas sa fin** | il s'ouvre sur son dernier événement et y reste quand le contenu grandit ; si l'on remonte pour lire, il compte les événements arrivés (« 3 nouveaux événements ») et ramène en bas d'un appui |

Le « suis-je en bas ? » est **mesuré** par `onScrollGeometryChange` quand la
plateforme sait le dire (iOS 18 / macOS 15), avec un repli déclaré pour iOS 17 : il
répond « oui », donc le journal suit — le comportement d'un journal qu'on vient
d'ouvrir, et le moins surprenant quand on ne peut pas mesurer.

**« Développer » suit la troncature réelle.** Le bouton n'apparaissait qu'au-delà de
120 caractères alors que la ligne en montre QUATRE : un message de six lignes
courtes — quatre-vingt-dix caractères — était tronqué sans aucun moyen de lire la
suite. Le seuil compte les lignes, avec une estimation prudente de la largeur
(40 caractères par ligne, la mesure d'un iPhone étroit) : mieux vaut offrir le
bouton pour rien que de cacher un texte.

### Ce qui attend remonte en tête

« Qui m'attend ? » est la question qu'on se pose en ouvrant l'application, et la
réponse était enterrée : il fallait déplier dix espaces et lire des pastilles de
huit points pour trouver la session bloquée sur une décision.

- une section **« Demande votre attention »** réunit, en tête de liste, les sessions
  qui attendent une décision ou dont la fin n'a pas été lue. Le tri est celui de
  l'urgence : une session bloquée *sur vous* passe avant une fin de tour qui vous
  informe ; à urgence égale, la plus récente d'abord. La session reste aussi à sa
  place dans son projet — la section précède l'arbre, elle ne le remplace pas ;
- l'en-tête d'un espace replié dit ce qui y attend — « 6 · 1 en attente », en orange
  quand quelque chose attend, le nombre seul sinon. Replier un dossier ne cache plus
  l'information qui comptait ;
- **les listes vides se disent** : « Aucune session » explique quoi faire, et une
  recherche sans résultat nomme le terme cherché.

Les trois lectures — pastille, tri d'urgence, compteurs — passent par
`EtatSession.de`, la règle unique de l'état d'une session listée : un compteur qui
compterait autrement que ce que la liste montre serait un second vocabulaire pour un
seul fait.

### La couche d'adaptation : trois manques, corrigés

Une revue d'interface (six réviseurs indépendants, puis vérification dans le code) a
relevé, sans se concerter, que l'application n'avait **aucune** couche d'adaptation : ni
tailles de texte dynamiques, ni libellés pour les lecteurs d'écran, ni respect de
« Réduire les animations », ni cibles tactiles conformes. Trois de ces quatre points sont
corrigés ici — le quatrième (Dynamic Type complet, qui demande de reprendre chaque taille
absolue) reste à faire, et le rapport d'audit le classe en finition.

| Manque | Ce qui a changé | Preuve |
|---|---|---|
| **VoiceOver muet sur les états** — l'information vivait dans une forme et une couleur | une phrase par ligne de session (`AfficheLigneSession.libelleAccessible`), par étape (`ParcoursDesEtapes`) et par machine (`EtatMachine.libelleAccessible`) ; l'indicateur décoratif est masqué pour ne pas dire deux fois la même chose | 6 tests, dont un qui vérifie que les cinq états de session ont cinq libellés **distincts** |
| **« Réduire les animations » ignoré** — une rotation en boucle infinie, et `EtatSession.anime` que personne ne lisait | l'indicateur relit le réglage et s'arrête net ; **les quatre carrés orange restent affichés**, immobiles : une animation supprimée ne doit pas emporter l'information | règle du modèle éprouvée (`anime` n'est vrai que pour `.enCours`) ; le rendu demande un appareil |
| **Cibles tactiles sous 44 pt** — boutons d'icône dessinés au plus juste | `cibleTactile()` : cadre de 44 pt et `contentShape` (sans quoi le cadre ne rendrait rien cliquable) sur copier une commande, coller et effacer un jeton, envoyer, interrompre, effacer la recherche | le modificateur est unique, donc la règle ne peut pas diverger d'un écran à l'autre ; macOS garde sa cible au pointeur |

Ce qui n'est **pas** affirmé : l'ordre de lecture réel, les contrastes en mode sombre, et
le rendu en taille d'accessibilité maximale. Ces trois-là demandent un appareil, et le
rapport d'audit les liste comme tels.

### Les étapes grisées restent lisibles

Le propriétaire avait demandé que les étapes suivantes d'un parcours soient grisées :
« pas besoin de rentrer dans leur détail ». La règle était appliquée trop loin — sur la
page « Ajouter un serveur », les étapes 2 à 4 sont déclarées « à faire » **par
construction** (on ne juge pas une machine qu'on n'a pas encore), donc la frontière ne
pouvait jamais avancer, et les étapes 3 et 4 restaient verrouillées à perpétuité, **sans
explication ni méthode** : « publier le port » et « installer le plugin » étaient
inatteignables depuis la seule page qui existe pour les enseigner.

Le verrou reste un **repère d'ordre** — ligne grisée, cadenas, « après l'étape N », et
les méthodes ne sont pas dépliées d'office, donc la page reste courte. Mais chaque étape
non franchie porte désormais son explication et un bouton **« Voir la méthode »**, la
règle vivant dans `EtapesServeur.presentation` où elle est éprouvée.

### Un défaut trouvé en regardant, pas en compilant

L'écran de journal s'ouvrait sur un en-tête correct et **« Journal (0 affichés) »**
pour une session de 48 évènements. La cause n'était pas le protocole : `ouvrir()`
existait dans le modèle mais **n'était appelé par aucune vue** — la sélection
remplissait le détail sans jamais demander le journal. Compiler ne pouvait pas le
voir ; le simulateur, si, en une capture.

Le chargement tient désormais à un `.task(id: session.id)` dans la vue du journal,
et non à un effet de bord de la sélection : changer de session relit le journal,
et l'écran ne peut plus mentir sur son contenu.

### Les gestes, et la surface macOS

Deux manques relevés par l'audit UX/UI, et comblés ensemble parce qu'ils disent la
même chose : l'application ne se pilotait qu'à l'appui simple, et sur le Mac, qu'à
la souris.

**Sur iPhone, les gestes qui manquaient.**

| Geste | Ce qu'il fait |
|---|---|
| Tirer la liste vers le bas | `modele.rafraichir()` — le suivi automatique est à trois secondes, mais il est **conditionnel** (« Suivre l'activité ») et il ne dit rien de la fraîcheur de ce qu'on regarde |
| Glisser une session vers la droite | « Vu » (si un rappel de fin est armé) et « Copier le titre » |
| Appui long sur une session | Les mêmes actions, plus « Copier l'identifiant » — la clé qui relie une session à ce que l'hôte en dit |
| Appui long sur une machine | « Se connecter », « Copier l'adresse », et « Oublier ce serveur » — **réservée à la machine courante**, parce que `oublierServeur()` oublie l'adresse mémorisée : l'offrir ailleurs aurait fait agir un bouton sur une machine non désignée |
| Copier une commande, choisir une machine, envoyer | Retour haptique (`.sensoryFeedback`) — trois choses qui se passent pendant qu'on regarde ailleurs |

Le glissement est réservé à iOS : sur macOS, `swipeActions` se compile mais aucun
matériel ne le produit. Le menu contextuel, lui, existe sur les deux plateformes —
c'est le seul chemin qui reste au clavier et sous VoiceOver.

**Sur macOS, les réglages et les raccourcis.** L'écran de réglages était **vide** et
s'ouvrait quand même, par un bouton de barre d'outils — deux choses que la directive
macOS déconseille. Il existe maintenant une scène `Settings`, donc l'entrée
« Réglages… » du menu et son **⌘,** ; le bouton de barre d'outils ne subsiste que sur
iOS, où la feuille est le lieu prévu.

| Raccourci | Effet |
|---|---|
| ⌘, | Ouvre les réglages (fourni par la scène `Settings`) |
| ⌘R | Rafraîchit sessions et machines |
| ⌘F | Donne le focus à la recherche — par une `FocusedValue`, la commande ne voyant pas les vues ; l'entrée est **grisée** quand aucune fenêtre ne publie l'action |
| ⌘↩ | Envoie le message en cours de rédaction. **Publié par le composeur lui-même** : l'entrée n'existe que si une session est ouverte *et* si l'hôte annonce l'écriture, et elle est grisée sinon — jamais un raccourci qui échoue en silence |

L'écran de réglages ne dit plus qu'il est vide : il porte l'état de **cet appareil**
(Tailscale, tailnet, exceptions ATS du paquet construit), le chemin du fichier de
diagnostic — copiable —, les versions, et la section **Réinitialiser** (voir plus bas). L'état de l'appareil y est à sa place : il
est la première étape du parcours de **chaque** machine, et il n'était lisible nulle
part quand aucune machine n'est connue — exactement l'état d'un appareil neuf.

**Ce que cela a demandé, et qui ne se voyait pas.** Le modèle vivait dans la vue :
une scène `Settings` et des commandes de menu doivent parler à **celui de la
fenêtre** — sinon ⌘R rafraîchit une instance que personne ne voit, et les réglages
décrivent un autre appareil que celui affiché. `VuePrincipale` reçoit donc un modèle
injectable, et l'application macOS le tient au niveau de la scène.

**Trois finitions, trouvées en regardant les captures.** La légende d'une vignette
passait de 9 points à `.caption2` : neuf points est sous le minimum de la directive,
et c'est la seule ligne qui dit « pas de DSH ». La recherche portait **trois
épaisseurs** — une matière sur une bande elle-même en matière, plus un contour —, ce
que la documentation du SDK 26 demande précisément d'éviter ; elle reprend le dessin
du composeur. Et le nom d'une machine s'écrivait **deux fois** sur sa page (barre de
titre de fenêtre et bande d'identité), à quarante points d'écart.

### Trois règles d'affichage, sorties de la vue et éprouvées seules

Trois décisions « quel écran, quelle coche, quel geste » vivaient dans la vue, en
enchaînements de conditions. Elles sont maintenant trois types purs, éprouvés sans
interface — et les défauts qu'elles ont corrigés étaient invisibles à la compilation.

| Règle | Type | Le défaut qu'elle a corrigé |
|---|---|---|
| Ce que le volet de détail montre | `DetailAffiche` | cinq branches qui finissaient sur « Aucune session ouverte » : écran vide au lancement sur macOS et sur iPad alors qu'une machine était sélectionnée |
| Ce qu'un appui sur une vignette fait | `GesteSurServeur` | la règle écrite à la main dans quatre vignettes : sélectionner, ou ouvrir la fiche si c'est déjà la cible |
| Quelle machine est sélectionnée | `SelectionParDefaut` | voir ci-dessous — c'est le défaut le plus retors des trois |

**LA RÈGLE DES DEUX TEMPS, POUR LES TROIS PLATEFORMES.** Le propriétaire l'a dite
ainsi : « sélectionner un autre serveur change la sélection — la pastille en haut à
gauche — et actualise l'espace de travail ; sélectionner une icône **déjà**
sélectionnée permet d'accéder à la page détail. »

Elle a demandé **deux** corrections, et la seconde ne se voyait que sur macOS et iPad :

1. **sur iPhone**, la vignette était *toujours* un `NavigationLink`, qui empile la page
   à chaque appui — quoi que dise la règle. Le premier appui ne pouvait donc pas se
   contenter de sélectionner, et l'infobulle (« un second appui ouvre sa page »)
   mentait. C'est le **mécanisme** qui suit maintenant la règle : un lien quand la page
   doit s'ouvrir, un bouton quand la machine doit être sélectionnée ;
2. **sur macOS et iPad**, `vise` figurait parmi les sources de la page : le volet de
   droite rouvrait la fiche dès le premier appui, donc le second ne servait à rien.
   `DetailAffiche` distingue maintenant `.selection(machine)` — page non ouverte — de
   `.serveur(machine)` — page ouverte —, et **seul le lancement** ouvre la page de la
   machine choisie par défaut : l'écran de droite n'est jamais vide au démarrage, mais
   un appui ne l'ouvre jamais. Entre les deux appuis, le volet dit laquelle est
   sélectionnée et ce que le second appui fera.

**« IL DOIT TOUJOURS Y AVOIR UN SERVEUR SÉLECTIONNÉ »** — la coche en haut à gauche de
la vignette, et sous elle les espaces de travail de ce serveur. Mesuré sur iPhone :
l'application se connecte **d'abord** à l'adresse mémorisée, et la liste des machines
n'arrive **qu'après**, publiée par cet hôte. Rien ne rattachait alors la machine jointe à
la cible : la liste s'affichait sans aucune coche, et le panneau des espaces restait vide.
Sur macOS l'ordre est inverse — on découvre, puis on se connecte —, donc le défaut ne s'y
voyait pas : *un défaut d'ordre se cache toujours dans la plateforme où l'ordre est
favorable.*

`SelectionParDefaut` distingue trois cas, et **la conséquence diffère** :

1. **l'adresse courante désigne une machine de la liste** → c'est elle (un fait) ;
2. **la liste vient de l'hôte et elle le désigne lui-même** (`estLocal`) → c'est lui
   (un fait aussi). Sans ce cas, aucune correspondance n'aboutissait : connecté à
   `127.0.0.1:3080`, l'hôte publie son nom de tailnet, pas la boucle locale ;
3. **aucun des deux** → au LANCEMENT seulement, la première vignette (le choix demandé).

Les deux premiers cas **attachent** la machine à la cible ; le troisième la **remplace**.
La distinction n'est pas cosmétique : mesuré sur simulateur, attacher en passant par
`choisir` a fait apparaître la coche **et disparaître les six sessions et les sept espaces
de travail** — la seule raison était un changement d'écriture d'adresse. Le marqueur
`estLocal` n'est utilisé que quand la liste vient de l'hôte : sur macOS, il désigne
*notre* machine, pas celle à qui l'on parle.

**Ce qui est prouvé de cette règle** : 15 tests (`SelectionParDefaut`, dont les deux qui
tiennent le lancement : la page s'ouvre au démarrage, aucune page ne s'ouvre après une
réponse de l'hôte) ; 13 tests (`DetailAffiche`, dont « les deux temps » et « la session
reste prioritaire ») ; 5 tests (`GesteSurServeur`) ; et deux captures du simulateur
iPhone — avant (deux vignettes, aucune coche, espaces vides) et après (coche sur
« MacBook Air », son nom au-dessus des espaces, six sessions).

### Ce qui se retrouve à la réouverture

L'application repartait à zéro à chaque lancement : espaces repliés, aucune session
ouverte, mode d'envoi remis à « à la suite ». Aucun de ces trois choix ne se reprend
à chaque ouverture — ce sont des **choix durables**, et les redemander coûtait des
gestes répétés à chaque lancement.

Ils vivent maintenant dans `EtatDeNavigation`, écrit par `Persistance` — le seul
endroit du paquet qui touche au disque. Deux règles rendent la restauration sûre :

1. **la session mémorisée est revalidée** contre la liste que l'hôte vient de rendre :
   rouvrir un journal disparu afficherait un écran vide sous un titre oublié ;
2. **rien de ce qui est retenu n'est une donnée de session** — ni titre, ni journal,
   ni projet —, seulement des identifiants opaques, revalidés à l'usage.

Les espaces sont **triés à l'écriture** : un `Set` encodé en JSON n'a pas d'ordre, et
deux écritures du même ensemble produisaient deux fichiers différents, ce qui rendait
un test de persistance instable pour rien.

**Le collage du jeton passe par le bouton système sur iOS** : lire
`UIPasteboard.general.string` sur un appui déclenche la bannière « Collé depuis … »,
alors que l'utilisateur **demande** ce collage. `PasteButton` exprime la même intention
au système, qui accorde l'accès sans bannière. La validation, elle, reste la même des
deux côtés (`ModeleApp.jetonPlausible`), et le message d'échec n'est écrit qu'une fois.

### « Réinitialiser l'application » : le seul geste irréversible, et ce qu'il dit

L'application garde des secrets et des préférences, et **rien** ne permettait de les
effacer : une adresse mémorisée par erreur ne partait qu'en désinstallant, et des jetons
d'appareil de machines qu'on ne visite plus restaient vivants. Les réglages portent donc
une section **Réinitialiser**, avec un bouton destructif, une confirmation, et un compte
rendu.

**CE QU'ELLE EFFACE.** Les jetons d'appareil **tous**, y compris ceux d'hôtes qu'on ne
visite plus — c'est le cas que le geste doit couvrir, et `GardienDeJetons.effacerTout()`
énumère au lieu de supprimer « ceux qu'on connaît » ; l'adresse et le nom mémorisés ;
les préférences par serveur ; l'état de navigation (espaces dépliés, mode d'envoi,
session consultée) ; le réglage des alertes ; le fichier de diagnostic.

**ET ELLE REFERME LA PAGE OUVERTE** — correction signalée à l'usage : « il y a le même
problème suite à la réinitialisation sur macOS, il faudrait que la page s'actualise ».
Elle effaçait tout sauf ce qu'on avait sous les yeux : la fiche de la machine oubliée
restait affichée, avec un verdict calculé sur un jeton qui n'existait plus. La remise à
zéro passe par `oublierServeur`, qui appelle `fermerPage` — un seul chemin, donc un seul
endroit à éprouver, et le test ouvre une page AVANT de remettre à zéro (sans quoi
l'assertion serait vraie à vide : vérifié par mutation, le correctif retiré, il échoue).

**CE QU'ELLE NE TOUCHE PAS, ET QUI EST DIT À L'ÉCRAN.** Le **jeton du harness**, sur le
Mac : il vit dans son coffre, pas dans cette application. Et le **fichier d'amorçage**
déposé à la main : l'application ne le crée jamais, le supprimer serait effacer le
travail de quelqu'un d'autre — mais il **ré-amorcera** au lancement suivant, donc une
réinitialisation qui se tairait serait un mensonge par omission. Le compte rendu le
nomme.

**LE DÉFAUT QUE LES TESTS ONT TROUVÉ, ET QUI SE SERAIT VU PLUS TARD.** `toutOublier()`
retire les clés du disque ; le modèle, lui, gardait en mémoire ce qu'il avait **lu**
(`navigation`, `preferences`). La première écriture venue — un espace qu'on déplie, un
mode d'envoi qu'on change — les réécrivait : l'appareil se disait vierge et se réveillait
avec les réglages d'hier. `reinitialiser()` remet donc aussi les miroirs à zéro, et un
test le tient : mesuré, sans cette remise à zéro, il échoue sur `modeEnvoi` (`.steer` au
lieu de `.queue`) et sur `sessionConsultee` (`session-1` au lieu de `nil`).

**LE COMPTE RENDU DIT DES NOMBRES, PAS DES INTENTIONS.** `effacerTout()` ne compte que
les suppressions **réussies** — annoncer « 3 » parce qu'on a *demandé* trois
suppressions serait un compte rendu faux —, et l'écran affiche « aucun jeton n'était
gardé » sur un appareil déjà propre, jamais « 0 jeton » comme un échec. Le mot
« trousseau » a été retiré de cette ligne : sur macOS les jetons vivent en mémoire
(`GardienParDefaut`), pas dans le trousseau, et la phrase doit être vraie des deux côtés.

**LA CONFIRMATION ELLE-MÊME A ÉTÉ MESURÉE.** Une action irréversible derrière une touche
réflexe serait un défaut de sécurité : ÉCHAP déclenche-t-il « Tout effacer » ? Mesuré sur
une sonde SwiftUI isolée, à la structure exacte de `VueReglages` : **ÉCHAP annule**,
**RETOUR n'agit pas** (aucun bouton par défaut), et le clic explicite sur « Tout effacer »
déclenche bien l'action — contrôle positif compris, sans quoi « ÉCHAP annule » ne
prouverait rien. La sonde est versionnée dans `Sondes/dialogue` avec sa procédure
(`Sondes/README.md`).

### Deux points de l'audit qu'on ne corrige PAS, et pourquoi

Ils figuraient au plan d'actions ; ils sont tranchés ici, pour qu'on ne les
redécouvre pas comme des oublis.

- **L'écran de lancement reste vide** (`UILaunchScreen` sans contenu). La directive
  demande un écran « presque identique au premier écran », **sans texte ni logo** :
  le premier écran est une liste sur le fond système, et un dictionnaire vide donne
  exactement ce fond. Y mettre une image de marque serait une infraction, pas une
  finition. Ce qui manquait au premier lancement n'était pas là — c'était le
  **jeton**, et il est traité plus haut.
- **`PrivacyInfo.xcprivacy` n'est pas livré.** Le manifeste est exigé pour un envoi
  à l'App Store, et cette application n'est ni signable ni soumise en l'état (aucun
  compte développeur, cf. « Amorce par fichier »). Livrer un manifeste non éprouvé
  serait une promesse non tenue — la RÈGLE #5 du dépôt. Il sera écrit le jour où
  une soumission sera décidée, et il devra alors déclarer `UserDefaults` (raison
  `CA92.1`) et l'horodatage des fichiers lus.

### Ce qui reste non prouvé

- **Les gestes eux-mêmes.** Le glissement, l'appui long et le retour haptique sont
  écrits, compilés, et leurs actions sont celles du modèle — éprouvées par ailleurs.
  Mais aucun n'a été **déclenché** : cet environnement n'injecte pas de glissement
  dans une liste, et un retour haptique n'existe pas sur un simulateur, faute de
  moteur. Ce qui EST prouvé de cette tranche, c'est le menu contextuel macOS
  (énuméré dans le menu de l'application) et la scène `Settings` (ouverte par le
  menu et capturée).
- **L'EFFET d'un envoi par ⌘↩.** Le câblage est prouvé — l'entrée s'active quand un
  composeur est à l'écran, et seulement là —, mais l'envoi n'a pas été déclenché :
  appuyer sur ⌘↩ dans une session réelle y **injecterait un message**, et un test
  ne doit pas écrire dans la conversation de quelqu'un.
- **L'EFFET de ⌘R et de ⌘F.** Les deux entrées sont déclarées — énumérées dans le
  menu « Présentation » de l'application lancée — et leur cible est du code
  compilé. La frappe elle-même n'a pas été observée : `rafraichir()` n'écrit pas de
  trace, et le focus d'un champ ne se lit pas de l'extérieur.
- **La réouverture ELLE-MÊME n'a pas été observée.** L'aller-retour de l'état de
  navigation est éprouvé par deux tests (écriture, relecture par un second modèle,
  revalidation de la session), et le chemin d'écriture est celui du modèle. Mais
  rouvrir l'application et la voir revenir sur la même session n'a pas été constaté
  en capture : cela demande d'ouvrir un journal, de quitter, de relancer — trois
  gestes que cet environnement ne sait pas injecter dans la liste.
- **Le multitâche iPad et le clavier/pointeur** n'ont pas été essayés : la HIG les
  attend d'une application iPad, et rien dans le code ne s'y oppose — mais « rien ne
  s'y oppose » n'est pas une mesure.
- **La notification ELLE-MÊME n'a pas été observée.** Ce qui est prouvé, c'est la
  DÉCISION (9 tests, dont un canal espion qui vérifie qu'aucune alerte ne part
  quand elles sont éteintes) et la garde qui empêche le plantage hors paquet. La
  bannière du système, elle, demande un paquet signé, une autorisation accordée à
  la main, et une session qui se met réellement à attendre — trois choses que cet
  environnement ne fournit pas.
- **Le titre des menus FOURNIS PAR LE SYSTÈME reste en anglais** quand
  l'application est lancée comme binaire nu (`swift run`) : elle n'a alors ni
  paquet ni `Info.plist`, donc aucune région de développement, et « Settings… »
  s'affiche là où l'écran lui-même est en français. Le paquet iOS, lui, déclare
  `CFBundleDevelopmentRegion = fr`. **Non vérifié dans un `.app` macOS**, qui n'est
  pas produit par ce paquet.

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
  « Enregistrement de l'écran » — **accordée sur cette machine depuis le 14 septembre
  2026**, et deux captures de la fiche ont été prises ce jour-là. Avant cela,
  l'application **compilait et démarrait sans planter**
  (processus vivant après 6 s, fenêtre 1100×720 présente), mais son rendu n'avait pas été
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
- **L'effacement des jetons dans le trousseau d'un iPhone RÉEL.**
  `TrousseauDeLaMachine.effacerTout()` est écrit, compilé, et sa requête est close sur
  le service `org.example.dsh-remote` — elle ne peut donc pas viser le mot de passe
  d'une autre application. Mais il n'est pas exercé par un test : sur macOS le gardien
  par défaut est **en mémoire** (`GardienParDefaut`), et les tests emploient une
  doublure. Ce qui EST prouvé, c'est le compte rendu (6 tests, dont « aucune
  suppression non réussie n'est comptée »), la remise à zéro du modèle, et le fait que
  le geste est à l'écran avec sa confirmation. La mesure qui manque — appairer un
  iPhone, réinitialiser, vérifier que l'appairage est bien perdu — se fait sur
  l'appareil, et elle coûte un réappairage.
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

**Deux défauts du tool lui-même, trouvés en s'en servant.** `sessions` affichait
l'identifiant **coupé à 30 caractères** — or cet identifiant est l'argument de `journal`,
`flux`, `prompt` et `annuler` : l'outil imprimait une valeur qu'il refusait ensuite, et
l'hôte répondait `404`. Il est désormais affiché en entier (`session-` + UUID = 44
caractères, la largeur est exacte et non devinée).

Et ce `404` se lisait **« cet hôte ne sait pas échanger un code d'appairage : son plugin
est plus ancien que cette application »** — un remède faux, qui envoie mettre à jour un
plugin alors que la session demandée n'existe pas. La cartographie des statuts dépend
maintenant de la route : sur l'échange d'un code, `404` = route inconnue, donc plugin
trop ancien ; **ailleurs**, `404` = la session n'existe pas, et le message dit ce que
l'hôte dit :

```text
$ dsh-remote-ctl http://127.0.0.1:3080 journal session-00000000-0000-4000-8000-000000000000
erreur : refus de l'hôte : session inconnue (HTTP 404)
```

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

**LE BINAIRE QUE VOUS LANCEZ N'EST PAS TOUJOURS CELUI QUE VOUS VENEZ DE CONSTRUIRE.**
`swift run` ouvre le binaire du dépôt (`.build/`), mais l'application du quotidien est
le PAQUET installé, `/Applications/DSH Remote.app` — et il ne se met pas à jour tout
seul. Constaté à la dure : une refonte entière de la fiche a été vérifiée en capture
sur `.build/` alors que l'application réellement ouverte datait d'une heure avant, et
le propriétaire avait raison de dire « tu dois faire un rebuild ». Pour livrer :

```bash
Scripts/empaqueter-app-macos.sh --installer   # construit, VÉRIFIE l'empreinte, remplace, ouvre
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

**LES RESSOURCES SWIFTPM, SANS QUOI L'APPLICATION MEURT APRÈS AVOIR SEMBLÉ SE
LANCER — mesuré le 14 septembre 2026.** Le paquet n'était assemblé qu'avec
l'exécutable et l'icône. Or les traductions vivent dans
`DSHRemote_DSHRemoteKit.bundle`, que SwiftPM construit **à côté** de l'exécutable.
Le script annonçait donc « paquet pret », l'empreinte était la bonne, la signature
valide — et l'application mourait au premier mot traduit :

```text
DSHRemoteKit/resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named DSHRemote_DSHRemoteKit
```

Trois rapports de plantage ont été produits avant que la cause soit lue, et le
paquet fonctionnait **avant** les traductions, parce que `Bundle.module` n'était
alors jamais sollicité. Le script copie désormais le paquet
`DSHRemote_DSHRemoteKit.bundle` dans `Contents/Resources` et le dit dans sa sortie
(`[macos] tables de traduction : N fichier(s)`) ; `Traduction` le cherche lui-même
là, parce que l'accesseur de SwiftPM vise d'abord la RACINE du `.app` — et
`codesign` refuse alors le paquet (« unsealed contents present in the bundle
root »). Un paquet qui ne se lance pas ne doit pas pouvoir s'annoncer prêt.

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
│   ├── DecouverteServeurs.swift  # machines du tailnet : découverte par l'hôte, ou locale sur macOS
│   ├── Tailscale.swift    # état de Tailscale sur cette machine
│   ├── FluxSession.swift  # WebSocket temps réel
│   ├── Reconnexion.swift  # la politique de reconnexion (valeur pure, éprouvée)
│   ├── RemoteClient.swift
│   ├── ModeleApp.swift    # état de l'application — la vue ne parle jamais au réseau
│   ├── AppariementDeMachines.swift  # quelles adresses désignent la MÊME machine (règles pures)
│   ├── ModeleApp+Derivations.swift  # ce que l'interface LIT du modèle (dérivations, sans état)
│   ├── ModeleApp+Ecriture.swift     # composer, envoyer, annuler — et les règles qui évitent le doublon
│   ├── AdresseMachine.swift         # http ou https, décidé par ce que le paquet autorise
│   ├── CheminReseau.swift           # NWPathMonitor : l'état du chemin, et la règle de reprise (pure)
│   ├── ConfigurationReseau.swift    # la configuration PARTAGÉE des deux clients, et ses deux dissymétries mesurées
│   ├── EtatMachine.swift  # l'état d'une machine : MÊMES MOTS au panneau latéral et sur sa page
│   ├── ExceptionATS.swift # ce que CE paquet autorise en clair, lu dans son propre Info.plist
│   ├── ConseilAdresse.swift  # l'adresse à conseiller, décidée par ce que le paquet autorise
│   ├── CibleTactile.swift # la cible de 44 pt des boutons d'icône
│   ├── Vues.swift         # liste des sessions
│   ├── VueJournal.swift   # journal d'une session
│   ├── FicheServeur.swift # LA page — quatre bandes : verdict, parcours, réglages, détail technique
│   │                      #   `serveur == nil` en fait la page « Ajouter un serveur »
│   ├── ParcoursDesEtapes.swift  # les cinq constats, en diagnostic ou en objectifs
│   ├── Demarches.swift    # publier le port, installer le plugin : les deux procédures partagées
│   ├── FeuilleAdresse.swift  # adresse ET jeton — le seul écran qu'un appareil neuf puisse ouvrir
│   ├── VueEcriture.swift  # composeur (écrire, interrompre)
│   └── VueReglages.swift  # cet appareil, alertes, diagnostic, réinitialisation, versions
├── DSHRemoteCtl/          # tool de validation (macOS)
│   └── main.swift
└── DSHRemoteApp/          # application macOS : `swift run DSHRemoteMac`
    └── main.swift
Tests/
└── DSHRemoteKitTests/     # décodage des charges utiles réelles, écriture, rappels de fin
Sondes/
└── dialogue/              # sonde isolée : que fait ÉCHAP sur une confirmation destructive ?
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

### Le battement de cœur : une socket morte SANS LE DIRE

**Le défaut.** Une connexion TCP peut mourir sans fermeture et sans erreur — la radio
d'un téléphone perd les paquets — et `receive()` reste alors suspendu. Rien ne vérifiait
que les pings revenaient : le serveur envoie le sien toutes les 30 s et la plateforme y
répond toute seule, mais personne ne lisait la réponse, ni d'un côté ni de l'autre.
L'écran affichait « En direct » sur un journal qui ne recevrait plus rien.

**Le remède, des deux côtés.** `FluxSession` envoie son propre ping toutes les **15 s**
et exige le pong en **5 s** (`FluxSession.Battement`) ; sans pong, la séquence se termine
par une `erreur` et le modèle rouvre avec `depuisSeq`. Le serveur, lui, ferme en `1008`
après **deux pings sans aucun pong** — un filet de sécurité pour les clients qui ne
battent pas la mesure, l'application voyant la coupure bien avant.

**Les valeurs sont mesurées, pas choisies.** Quinze secondes, c'est deux fois moins que
le ping du serveur : une socket morte est vue en vingt secondes au pire. Cinq secondes
pour le pong laissent la place à un réveil radio normal (mesuré : 412 ms) sans laisser
passer une vraie coupure. Le type `Battement` est injectable pour une seule raison : un
test qui devrait attendre quinze secondes pour éprouver une coupure ne serait pas lancé.

**Éprouvé sur le fil**, contre le serveur d'essai Node (`Outils/serveur-flux-essai.mjs`),
dans ses deux sens :

| Essai | Ce que le serveur fait | Ce qui est vérifié |
|---|---|---|
| `sourd` | répond au `demarrer`, puis **jamais** aux pings | la base arrive (la socket a vécu), puis le client conclut seul — et il a bien envoyé son ping |
| normal | répond à chaque ping | le flux **survit** à plusieurs battements, sans aucune erreur |

**Trois autres défauts corrigés dans la même pièce.** L'échec de `send` du `demarrer`
était ignoré (`{ _ in }`) : socket ouverte, aucun message parti, journal figé sur
« En direct » — il est maintenant traité comme une erreur de flux, donc une reconnexion.
La demande d'ouverture était un JSON **interpolé** (`"session":"\(identifiant)"`), ce qui
marchait par chance sur un `session-<uuid>` ; elle passe par `JSONEncoder`, et un
identifiant hostile (`"`, `\`, saut de ligne) traverse l'encodage intact. Enfin le
battement démarre **tout de suite**, et non après l'envoi : sur une socket qui ne se
connecte pas, `send` ne rend jamais la main, et un battement qui l'attendrait ne
commencerait jamais.

### Le statut poussé, et le chemin réseau observé

**LE STATUT ARRIVE PAR LE FLUX, PLUS SEULEMENT PAR LA BOUCLE.** L'hôte pousse
`{ "type": "statut", "statut": "en_cours" }` sur le flux de la session concernée, à
partir d'`agent/status` du harness. Le client le décode en `MessageFlux.statut`, et
`ModeleApp.appliquerStatut` met à jour **cette** session — jamais une autre, jamais une
session inconnue (elles n'existent pas encore dans la liste), et jamais sous une
génération périmée. La pastille s'allume donc en quelques millisecondes au lieu des trois
secondes de la boucle HTTP. **Un statut n'est pas un enregistrement** : il ne porte aucun
`seq`, ne compte pas comme un évènement, et ne fait pas avancer le curseur de reprise —
le confondre ferait sauter des enregistrements à la reconnexion.

**LE CHEMIN RÉSEAU EST OBSERVÉ EN CONTINU** (`NWPathMonitor`, `CheminReseau.swift`).
La détection du tailnet restait une mesure ponctuelle (`getifaddrs`) : juste, mais muette
sur les changements — activer Tailscale, couper le Wi-Fi, passer en 5G, sortir d'une zone
blanche ne s'apprenaient qu'à l'échec de la requête suivante. L'observateur notifie ces
changements, et le modèle en fait trois choses : il **remesure** le fait « cet appareil
est sur le tailnet » (l'observateur le déclenche, il ne le remplace pas : iOS ne publie
pas l'état d'un tunnel VPN), il **reprend** ce qui avait échoué quand le chemin revient
sans cible jointe, et il **espace** le suivi sur un chemin coûteux ou en « données
réduites » — sans jamais le couper, ce qui rendrait les pastilles fausses.

**CE QUI EST ÉPROUVÉ, ET CE QUI NE L'EST PAS.** La RÈGLE est pure et éprouvée sans
réseau (`CheminReseauTests`) : les deux conditions de la reprise — chemin présent ET
cible non jointe, les deux défauts opposés qu'elles séparent — et l'espacement. Le
CHEMIN LUI-MÊME ne l'est pas : `NWPathMonitor` ne se pilote pas depuis un test, et
couper le réseau de la machine qui exécute la suite n'est pas un test qu'on lance. Ce qui
reste dans l'adaptateur ne décide rien : il traduit un `NWPath` en état et prévient.

### Déclaration de confidentialité, et ce qu'elle affirme

`App/PrivacyInfo.xcprivacy` est **écrit à la main**, référencé par le projet Xcode, et sa
présence dans le paquet construit est **vérifiée** (`plutil -p
DSHRemote.app/PrivacyInfo.xcprivacy` sur une construction simulateur : le fichier est là,
et c'est bien celui-là). Son contenu dit deux choses, et les deux sont vérifiables dans le
code : aucune donnée collectée, aucun suivi (`NSPrivacyTracking = false`), et **une seule
API à raison obligatoire** — `UserDefaults`, pour les préférences, avec la raison
`CA92.1`. Le jeton d'appareil n'y est jamais : il vit au trousseau.

**La construction simulateur nommait un appareil précis** (« iPhone 17 Pro ») et ce nom a
cessé de résoudre quand les runtimes installés ont changé : `xcodebuild` refusait la
construction en listant des destinations macOS et watchOS. Le script construit désormais
pour `generic/platform=iOS Simulator`, et la construction passe (`BUILD SUCCEEDED`).

### La configuration réseau est PARTAGÉE — et le flux n'attend pas le réseau

`RemoteClient` et `FluxSession` construisaient chacun leur `URLSessionConfiguration`, et
elles avaient divergé : le client HTTP portait des délais mesurés, le flux aucun. Elles
viennent maintenant de `ConfigurationReseau`, avec **deux dissymétries qui sont des
mesures**, pas des oublis :

- **`waitsForConnectivity` va aux requêtes, jamais au flux.** Recopier le drapeau — l'«
  alignement » qui semblait évident — a fait **pendre** le client : vers
  `http://127.0.0.1:1`, le test de flux a été tué après **90 secondes**, alors qu'il
  passait en quelques millisecondes avant. Sur un flux, l'attente de connectivité du
  système se substitue au lieu de rendre l'échec, et rien ne la borne. Le flux a mieux :
  un échec rapide, et la politique de reconnexion (`Reconnexion`).
- **Le délai de ressource du flux n'est pas `max(delai, 120)`.** Il borne la durée
  TOTALE d'une tâche : recopié des requêtes, il couperait le direct toutes les deux
  minutes, en boucle. Il reste celui de la plateforme (sept jours), et un test le fixe
  pour que personne ne « corrige » cette dissymétrie.

### La reconnexion est AUTOMATIQUE — et la reprise, c'est ce qui la rend gratuite

**Le défaut que ça corrige, et il était bête.** Le protocole a été conçu pour la
reprise : `depuisSeq` évite de renvoyer au client ce qu'il possède déjà, et le serveur
sonde le journal toutes les 750 ms précisément pour ça. Mais le client s'arrêtait à la
première erreur de transport : `enDirect = false`, et **il fallait rappuyer sur le
bouton**. Sur un iPhone, une bascule Wi-Fi ↔ cellulaire suffisait donc à figer le
journal — c'est-à-dire à annuler tout le bénéfice de `depuisSeq`.

| Règle | Valeur | Pourquoi |
|---|---|---|
| Premier délai | **1 s** | réessayer à zéro échoue presque toujours : le chemin réseau n'est pas encore revenu (mesuré ici : un `ping` tailnet passe de 6 ms à 412 ms au réveil de la radio) |
| Croissance | ×2, puis plafond à **30 s** | au-delà, une coupure longue ressemblerait à un flux mort ; en deçà, une panne durable produirait 120 requêtes par heure pour rien |
| Quota | **20 tentatives** (~6 min) | le cas d'échec définitif est un **jeton révoqué** (`401`) : il ne se répare pas en réessayant, et une boucle infinie ferait clignoter l'écran pour toujours |
| Remise à zéro | sur un **contenu reçu**, jamais à l'ouverture | une socket qui s'ouvre puis se referme aussitôt (hôte qui refuse, session inconnue) ne prouve rien : réinitialiser à l'ouverture ferait boucler à une seconde indéfiniment |

**LA POLITIQUE EST UNE VALEUR PURE** (`Reconnexion.swift`) : on lui donne un nombre
d'échecs, elle rend un délai. C'est ce qui permet de l'éprouver sans couper un réseau
ni attendre — 5 tests, dont le produit « délai × quota » (plus de cinq minutes de
panne couvertes, moins d'un quart d'heure).

**LA REPRISE ELLE-MÊME EST ÉPROUVÉE SUR LE FIL**, contre un vrai serveur WebSocket
(Node, sans dépendance, dans `Tests/DSHRemoteKitTests/Outils/serveur-flux-essai.mjs`) :
il accepte deux connexions, **coupe la première brutalement** — pas de trame de
fermeture, comme un Wi-Fi qui s'endort — et **note ce que le second `demarrer` a
porté**. Le test lit cette note :

```
connexion=1 depuisSeq=absent     ← la première demande ne reprend rien
connexion=1 coupure=brutale
connexion=2 depuisSeq=2          ← la reprise porte le seq connu
```

**ET LA BOUCLE DU MODÈLE EST ÉPROUVÉE À PART**, contre un faux hôte complet
(`Outils/serveur-modele-essai.mjs`, HTTP **et** WebSocket) qui coupe les **deux
premières** connexions puis laisse vivre la troisième. C'est nécessaire : le modèle
refuse d'ouvrir un flux sans avoir joint l'hôte par HTTP, donc un serveur qui ne
parle que WebSocket ne peut pas éprouver sa boucle. Le test lit la note :

```
connexion=1 depuisSeq=absent → coupure
connexion=2 depuisSeq=3      → coupure      ← la reprise AVANCE
connexion=3 depuisSeq=3      → maintenue    ← et ne recule jamais
```

…et, à l'écran, **aucun doublon** : le faux hôte renvoie exprès, dans la base de
reprise, un enregistrement que le client connaît déjà.

**CE TEST A ATTRAPÉ UN DÉFAUT RÉEL, APRÈS LE PREMIER COMMIT.** Ma garde de
reconnexion exigeait `sessionOuverte?.id == identifiant` — or `sessionOuverte` n'est
renseigné qu'**après** une lecture de journal réussie. Une session dont la lecture
échoue (ou n'a pas encore abouti) n'aurait donc **jamais** repris son flux, tout en
affichant « En direct » : le défaut exact que ce lot corrige, reproduit une fois de
plus par une garde trop stricte. La garde lit maintenant `journalPour`, la clé du
journal affiché, posée dès l'ouverture et effacée au changement de cible.

**ET UN SECOND DÉFAUT, DANS LE TEST LUI-MÊME** : « Reconnexion… » n'existe
qu'**entre deux tentatives** — la suivante l'efface dès qu'elle reçoit un contenu.
La première version attendait le journal du serveur, PUIS relisait le libellé : elle
échouait une fois sur deux, parce que la tentative suivante avait déjà abouti. Un
état transitoire se **guette** (sondage serré sur la durée de la boucle), il ne se
relit pas à un instant choisi. Trois exécutions consécutives de la suite le
confirment, plutôt qu'une seule.

**TROIS ÉTATS DANS LA BARRE D'OUTILS, PAS DEUX** : « En direct », « Suivi arrêté », et
« Reconnexion… (n/20) ». Le troisième n'est pas un ornement : sans lui, une coupure de
dix secondes afficherait « En direct » sur un journal qui ne reçoit rien. Le geste de
l'utilisateur, lui, arrête **aussi** la reconnexion — sinon « Suivi arrêté » se
rallumerait tout seul une seconde plus tard.

---

## Choix de conception

- **Aucun en-tête `Origin`.** Le serveur refuse en `403` toute requête qui en porte un —
  c'est sa barrière anti-navigateur. Le client en ajouterait un qu'il casserait son
  propre accès ; c'est commenté dans le code pour que personne ne « corrige » ça.
- **Aucun cookie, aucun cache.** `URLSessionConfiguration.ephemeral`, cache vidé,
  cookies refusés : un journal de session n'a rien à faire sur disque, et une réponse
  périmée induirait l'utilisateur en erreur.
- **Un porteur ne se présente QU'À l'hôte dont il est le secret.** La sonde de
  découverte interroge les machines du tailnet : elle n'envoie **aucun** jeton, et un
  `401` lui suffit à conclure « DSH est là » — le service a répondu, seul le porteur
  manquait. Avant, le jeton de la cible partait vers chaque machine interrogée, qui
  pouvait le rejouer ; c'est la règle du modèle (chaque hôte a SON jeton) poussée
  jusqu'au bout. Éprouvé par `SondeTests` (quatre machines, quatre porteurs vides).
- **Le transport est compressé, et le client n'a rien à faire.** Mesuré : le serveur
  du harness compresse déjà ses réponses (`Content-Encoding: gzip`), et `URLSession`
  annonce `Accept-Encoding: gzip, deflate` — ni `br`, ni `zstd`. Sur l'instance
  réelle : 138 429 → 19 317 octets pour la liste (7,2×), 492 021 → 129 656 pour une
  page de journal (3,8×), corps identique après décompression. Détail et
  configuration dans le README du plugin ; c'est pourquoi **aucune ligne de
  compression n'existe côté Swift**.
- **Le registre de clients porte une EMPREINTE du jeton**, jamais le jeton. Sans elle,
  se ré-appairer sur la **même** machine — jeton révoqué, réinstallation, second scan du
  même QR — rendait le client gardé avec l'ANCIEN porteur : `401` sur toutes les routes
  jusqu'à éviction du registre ou redémarrage, sans qu'aucun écran ne dise pourquoi. Le
  raisonnement écrit dans le code (« un jeton ne change qu'en changeant de cible ») était
  faux pour le cas le plus courant. Éprouvé par `ConnexionTests`.
- **Les jetons macOS restent EN MÉMOIRE, et c'est décidé.** Le passage au trousseau a
  été envisagé au titre des finitions : il n'est PAS fait. L'application macOS est
  construite en ad-hoc (`Scripts/empaqueter-app-macos.sh`), et un élément de trousseau
  est lié à la signature : une reconstruction changerait l'identité, donc l'accès — au
  mieux une invite système à chaque lancement, au pire un secret perdu. La conséquence
  est DITE (le jeton d'un hôte distant est à recoller après un redémarrage) plutôt que
  subie sous forme d'invites. Sur iPhone, le trousseau garde tout.
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
| **L'hôte publie la liste des machines du tailnet** | `dsh-remote-ctl serveurs` → 4 machines : les 3 Macs **et `MiBook` (OS `windows`)** ; l'iPhone (`OS` `iOS`) est écarté |
| **Les espaces viennent du registre de l'hôte** | `dsh-remote-ctl <adresse> espaces` → 7 espaces, du plus récent au plus ancien, avec leur nombre de sessions |
| **Espaces par création, sessions par activité** | 3 tests : un espace ancien mais très actif reste sous un espace récent ; dans un espace, la session la plus active passe devant ; départage stable à date égale |
| **Un espace vide est représenté** | 6 tests sur les charges utiles de l'hôte : espace sans session marqué `sansSession`, appartenance par identifiant et non par chemin, « Sans espace » en dernier, repli sur `cwd` sans registre |
| **L'iPhone CONSOMME la découverte** | simulateur iPhone 17 Pro : les machines s'affichent avec icône et état, « hôte interrogé » sur la machine qui répond — aucun processus exécuté par l'application |
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
| **Un iPhone neuf peut saisir son premier jeton** | capture iPhone de la feuille « Adresse » (`--adresse`) : section « Jeton d'appareil », son bouton « Coller », le compte de caractères, puis « Se connecter » et « Tester l'adresse » — le champ qui manquait au seul écran qu'un appareil vierge puisse ouvrir |
| **Le conseil d'adresse suit ce que le paquet autorise** | capture iPhone du build AVEC exception : pied de page « Ce build autorise le clair vers le tailnet déclaré » ; 6 tests couvrent le paquet sans exception (il conseille `https://…`), l'exception inopérante, et un domaine qui n'est pas un sous-domaine |
| **Le remède d'un 401 mène à un champ qui existe** | test : le message ne dit plus « Réglages » (qui n'a plus de champ de jeton) et nomme les deux écrans qui en ont un |
| **Les étapes grisées restent lisibles** | capture iPhone (`--ajout --page-seule`) : étapes 3 et 4 grisées avec cadenas ET « Voir la méthode » dépliable ; test : aucune étape non franchie d'une liste de travail n'est sans méthode |
| **Les états sont dits en mots, pas seulement en couleur** | 6 tests : les cinq états de session ont cinq libellés distincts, la ligne annonce titre + état + matière, et une machine en ligne sans DSH n'est plus annoncée « en ligne » |
| **Le brouillon ne suit plus d'une session à l'autre** | 8 tests : cloisonnement par session et par hôte, changement de session qui ne perd plus le texte, et les trois cas de l'acquittement (vidé / préfixe retiré / texte divergent intact) |
| **Le jeton d'une page est celui de la machine affichée** | 5 tests sur le cloisonnement par hôte + 1 sur la reconnaissance de la boucle locale — celui-ci a attrapé la forme entre crochets de l'hôte IPv6 |
| **Un journal honnête** | 7 tests : une réponse en retard ne s'applique pas à la session affichée, l'erreur de lecture ne se montre que sous SA session, et « Développer » apparaît sur six lignes courtes comme sur une ligne de 400 caractères |
| **Ce qui attend remonte en tête** | 5 tests sur les compteurs d'un espace, leur pluriel, et l'ordre d'urgence ; capture iPhone du nouvel état vide « Aucune session » |
| **Les listes vides se disent** | capture iPhone : « Espaces de travail » vide affiche « Aucune session » et quoi faire, au lieu d'un « 0 session » qui laisse croire à une panne |
| **Les Réglages ne contiennent plus rien d'une machine** | capture iPhone : une phrase qui l'explique, puis les deux interrupteurs de sessions (préférences d'affichage, communes à toutes les machines) |
| **La page d'un serveur remplace le diagnostic dans le panneau latéral** | capture iPhone (`--page-seule`) : état, adresse, actions et jeton sur la page ; le panneau ne garde que pastille, légende et nom |
| **Une sonde annulée n'écrase plus le verdict** | journal : `fin : 1 serveur(s) DSH sur 2` puis `fin : 0` avant correction ; après, la sonde annulée ne publie rien et la page affiche « DSH · hôte interrogé » |
| **La page dit que le plugin manque, et donne la démarche** | capture iPhone de la page de MacMini (alors que l'app vise une autre machine) : constat nommé, la consigne à coller copiable, la vérification `curl` |
| **La démarche n'exige plus de redémarrage, et le rechargement d'onglet est une étape** | **expérience sur une instance vivante** (14 septembre 2026) : ligne retirée → `sante` `404`, le bouton disparaît seul ; ligne remise → `sante` `401`, le bouton **ne revient pas** ; onglet rechargé → il revient. **PID du harness inchangé** du début à la fin. Détail au README du plugin (P12) |
| **Le diagnostic de santé d'un serveur** | captures iPhone : conclusion (« Il reste une étape : « … » ») puis les cinq constats, sans verrou ; sur un Mac hors ligne, l'étape 2 avec ses commandes et les suivantes « à vérifier » |
| **Les étapes suivantes sont grisées, et lisibles** | capture iPhone : frontière (étape 2) avec sa méthode dépliée, étapes 3 et 4 grisées avec un cadenas, « après l'étape N », leur explication, et « Voir la méthode » — le détail n'est plus caché, seulement replié |
| **La page d'un serveur est structurée en quatre bandes, et partagée avec l'ajout** | captures macOS (`--page-seule`) : prêt, pas de DSH (MacMini), hors ligne — l'état est dit UNE fois, l'action proposée peut aboutir, les réglages sont repliés ; **et deux captures après la refonte** (une machine prête, `--ajout --page-seule`) : mêmes bandes, mêmes constats, la seule différence étant le mode |
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
| **La scène `Settings` existe et s'ouvre** | menu de l'application énuméré : « Settings… » présent ; fenêtre **Réglages** 900×552 ouverte par le menu et capturée — Tailscale installé, tailnet connecté, chemin du diagnostic, protocole version 1 |
| **Les réglages ne disent plus qu'ils sont vides** | captures de la fenêtre `Settings` (macOS) et de la feuille (`--reglages`) : trois sections, « Cet appareil », « Diagnostic », « À propos » |
| **⌘↩ s'active EXACTEMENT quand il peut agir** | mesuré par énumération du menu de l'application empaquetée : « Envoyer le message » **grisée** sans journal ouvert, **active** avec un journal ouvert. L'envoi lui-même n'a pas été déclenché : cela injecterait un message dans une session réelle |
| **⌘R et ⌘F sont déclarés** | énumération du menu « Présentation » : « Rafraîchir » et « Rechercher une session », entre « Show All Tabs » et « Enter Full Screen » |
| **Le bouton Réglages a quitté la barre d'outils macOS** | capture de la fenêtre principale : la barre ne porte plus que le basculeur de panneau ; l'engrenage ne subsiste que sur iOS |
| **La légende d'une vignette est lisible** | captures : « DSH · hôte », « pas de DSH » et « hors ligne » rendus en `.caption2` (11 pt), deux lignes autorisées |
| **La recherche n'a plus qu'un fond** | capture : un champ discret sur la bande en matière, au lieu d'une matière posée sur une autre plus un contour |
| **Le nom d'une machine ne s'écrit qu'une fois** | captures avant/après : barre de titre de fenêtre ET bande d'identité → barre de titre seule |
| **Deux machines qui partageaient « MacBook » se distinguent** | capture des données réelles : « MacBook Air » et « MacBook Pro », là où deux vignettes disaient « MacBook » — 5 tests sur `NomsCourts` |
| **L'état de navigation fait un aller-retour** | 2 tests : espaces triés relus par un SECOND modèle sur le même domaine ; une session mémorisée n'est rouverte que si l'hôte la nomme |
| **La réinitialisation efface TOUS les jetons, y compris d'hôtes oubliés** | 6 tests (`ReinitialisationTests`) : deux jetons dont un d'une machine qu'on ne visite plus, modèle ramené à neuf, diagnostic effacé, fichier d'amorçage CONSERVÉ **et nommé**, nombres réels, second passage qui dit « aucun jeton n'était gardé » |
| **Après elle, les réglages d'avant ne reviennent pas** | test dédié, et défaut RÉINTRODUIT pour vérifier qu'il le tient : sans la remise à zéro des miroirs, il échoue sur `modeEnvoi` (`.steer` au lieu de `.queue`) et sur `sessionConsultee` (`session-1` au lieu de `nil`) |
| **Le geste est à l'écran, et il annonce ce qu'il fait** | captures de l'application INSTALLÉE (`/Applications/DSH Remote.app`) : section « Réinitialiser », bouton destructif, pied nommant ce qui n'est PAS effacé, puis la confirmation « Réinitialiser l'application ? » avec « Annuler » et « Tout effacer » |
| **Une machine est TOUJOURS sélectionnée** | 13 tests (`SelectionParDefaut`) : adresse jointe, hôte qui se désigne lui-même, première vignette au lancement, adresse vide, liste vide, choix déjà fait jamais écrasé, marqueur `local` d'une découverte locale qui ne trompe pas — plus deux captures du simulateur iPhone (avant : aucune coche, espaces vides ; après : coche « MacBook Air », son nom, six sessions) |
| **ÉCHAP n'efface pas** | sonde SwiftUI isolée, à la structure exacte de `VueReglages` (`Sondes/dialogue`, procédure dans `Sondes/README.md`) : ÉCHAP → `ISSUE=annule` sur les deux variantes, RETOUR → rien (aucun bouton par défaut), clic sur « Tout effacer » → `ISSUE=destructif` — contrôle positif compris |
| **Le collage iOS ne lit plus le presse-papiers à l'insu de l'utilisateur** | `PasteButton` des deux côtés (feuille Adresse, page d'une machine) ; compilation iOS complète par `Scripts/construire-app-ios.sh --simulateur` → `BUILD SUCCEEDED` |
| **L'iPad en anglais, sur simulateur** | langue du simulateur passée à l'anglais, application relancée, capture : « DeepSeek Harness server », « Needs your attention », « Workspaces », « No session open », « DSH · host », « no DSH », « offline » — et les deux colonnes de l'iPad |
| **Le paquet iOS porte les deux tables** | dans le `.app` construit : `DSHRemote_DSHRemoteKit.bundle/{fr,en}.lproj/Localizable.strings`, **141 entrées** chacun, et `CFBundleLocalizations = [fr, en]` |
| **L'interface anglaise couvre AUSSI les messages du modèle** | capture de l'application empaquetée en anglais : « DeepSeek Harness server », « Needs your attention », « Workspaces », « No session open », « Choose a session in the list to read its journal. », et sous les vignettes « DSH · host », « no DSH », « offline » |
| **Le français reste le défaut** | capture de l'application empaquetée sans argument : « Serveur DeepSeek Harness », « Espaces de travail », « DSH · hôte », « Aucune session ouverte » |
| **Les deux tables de traduction sont complètes** | 4 tests : les deux tables se lisent depuis le paquet, elles portent EXACTEMENT les mêmes clés (89), aucune valeur n'est vide, une clé absente rend `nil` |
| **L'anglais s'affiche vraiment** | capture avec la langue forcée : « Settings », « This device », « Check now », « Alerts », « Diagnostic », « Copy the file path », « About » — et le champ de recherche « Search a session or a project… » |
| **Le français reste le défaut** | capture de l'application EMPAQUETÉE, sans argument : tout en français. Le défaut anglais ne touchait que le binaire nu, qui n'annonce aucune langue |
| **L'iPad est une cible, pas un mode compatibilité** | `UIDeviceFamily = [1, 2]` dans l'`Info.plist` construit ; installation et lancement sur un iPad (A16) simulé, captures en portrait et en paysage — deux colonnes, carrousel, espaces, recherche |
| **La colonne latérale était à l'étroit sur iPad** | défaut vu à l'écran : la contrainte de largeur ne s'appliquait qu'à macOS. Corrigée (340 pt minimum), et la capture montre le carrousel à trois chicons entiers au lieu de deux |
| **Les blocs de code sont reconnus, et la prose ne l'est pas** | 10 tests sur l'analyseur (`BlocsDeCodeTests`) : bloc avec ou sans langage, clôture non fermée, accents graves en milieu de ligne, fausse clôture, deux blocs, bloc vide, retour chariot Windows, clôture plus longue |
| **Le rendu est vu, pas déduit** | capture sur une session réelle : une sortie `bash` encadrée en monospace avec son bouton copier et « Développer », la prose de l'agent en texte ordinaire, et « the file … has been updated successfully » non encadré |
| **L'ancre `--session=` ouvre le bon journal** | capture : fenêtre titrée du nom de la session demandée, alors que la session restaurée était une autre |
| **Les alertes ne partent que sur un CHANGEMENT, et jamais pour ce qu'on regarde** | 9 tests : attente nouvelle, regroupement, session regardée, ordre attente-avant-fin, première observation muette, éteintes par défaut, refus système qui laisse l'interrupteur éteint, préférence relue au lancement |
| **`UNUserNotificationCenter` sans paquet fait AVORTER le processus** | mesuré sur un binaire nu : `NSInternalInconsistencyException: bundleProxyForCurrentProcess is nil`, code 134 — d'où la garde `AlerteurSysteme.possibles` |
| **La suite de tests ne touche plus aux préférences de la machine** | 33 tests construisaient `ModeleApp()` sur le domaine partagé ; ils sont tous isolés. Mesure : **12 échecs sur 15 exécutions** avant, **0 sur 20** après |
