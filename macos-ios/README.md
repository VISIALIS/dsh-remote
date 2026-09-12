# dsh-remote-swift — client Swift multiplateforme

Client **Swift natif** (macOS et iOS) du plugin [`dsh-remote`](../../plugins/dsh-remote/).
Une seule bibliothèque partagée porte le protocole, le transport et les modèles ; les
deux applications la consomment telle quelle.

Ce paquet ne contient **aucune** interface pour l'instant : il livre la bibliothèque et
un tool de validation. L'application SwiftUI est le jalon 2 (voir la feuille de route du
[README du plugin](../../plugins/dsh-remote/#feuille-de-route)).

MISE À JOUR — jalons 2 et 3 livrés : voir [Application](#application) et
[Flux temps réel](#flux-temps-reel).

---

## Application

```bash
swift run DSHRemote        # macOS : lit le jeton tout seul, aucune saisie
```

L'application réutilise **exactement** la bibliothèque du tool : les vues ne parlent
jamais au réseau, elles observent `ModeleApp`. Remplacer le transport ne demande donc
aucune retouche d'interface.

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
`DSHRemoteKit`, qui porte désormais tout le code réutilisable. Conséquence : il n'y a
plus de `swift run DSHRemote` ; l'application se lance depuis le projet Xcode, qui
couvre iOS **et** macOS.

### Installé sur l'iPhone — et l'adresse qui marche vraiment

**C'est fait.** Xcode a enregistré l'appareil, créé le profil de provisionnement, et
l'application est **installée et signée** (équipe `<equipe du proprietaire>`) :

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
printf 'mon-mac.mon-tailnet.ts.net\n' > Config/DomaineTailnet
```

Le script valide la forme du domaine, et **ne fait pas échouer le build** si le fichier
est absent : sans exception, l'application se construit et se lance, seule la connexion
HTTP vers un nom de domaine est refusée.

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

**L'icône suit le type de machine** : `macbook.air`, `macbook.pro`, `macmini`,
`macstudio`, `desktopcomputer` en repli. Elle apparaît à côté de l'adresse et
dans l'en-tête du journal.

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

Le rafraîchissement est fréquent parce qu'il est bon marché : la liste ne relit
pas les journaux, elle relit un résumé mis en cache côté serveur et interroge
l'état des agents. Il ne touche pas non plus au journal ouvert, pour ne pas
déplacer la lecture sous les yeux de l'utilisateur, et un échec passager ne
signale rien — l'utilisateur n'a rien demandé, il ne doit pas être interrompu.

### Trois états, dont un qui ne conclut pas

| Affichage | Sens |
|---|---|
| carrés orange qui tournent | `en_cours` — un tour s'exécute |
| anneau vide | état **inconnu** — la session n'est pas ouverte dans le processus |
| point bleu | `inactif` — chargée dans le harness, au repos |
| point vert | le harness n'a plus l'agent : session terminée |

L'anneau vide mérite une explication : dans une première version, l'état inconnu
s'affichait comme un point **vert**, donc comme une session terminée. L'interface
affirmait ainsi une conclusion que le serveur n'avait pas donnée — et sur une
installation où le harness n'avait pas encore rechargé le plugin, TOUTES les
sessions apparaissaient vertes, ce qui a été signalé comme un défaut. Un état
inconnu se montre comme inconnu.

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
  perdant ne doit pas primer sur une valeur exacte.
- **Le rattachement d'un sous-agent est INDICATIF.** L'en-tête d'un sous-agent ne
  nomme pas sa session parente : on les place sous l'espace de leur parent, sans
  prétendre à une exactitude que la donnée ne porte pas.

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

**2. Le bouton « Rafraîchir » ne pouvait rien faire.** La découverte est
impossible sur iPhone, donc appuyer réassignait une liste vide : ni succès, ni
erreur, ni changement. Il n'est plus proposé que là où le rafraîchissement change
quelque chose, et l'action utile — **« Tester l'adresse »** — a été ajoutée : elle
vérifie l'adresse ET le jeton, puis annonce le résultat (nombre de sessions, ou
la raison exacte de l'échec). Un bouton sans effet est un mensonge d'interface.

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

### Ce qui reste non prouvé

- **Le rendu de l'interface macOS.** `screencapture` exige l'autorisation
  « Enregistrement de l'écran ». L'application **compile et démarre sans planter**
  (processus vivant après 6 s, fenêtre 1100×720 présente), mais son rendu n'a pas été
  observé — alors que celui de la version iOS l'a été, par `simctl io screenshot`.
- **L'ouverture d'un journal depuis l'interface.** Les interactions système
  (accessibilité) sont refusées à cet environnement : je n'ai pas pu cliquer une ligne
  dans le simulateur. La lecture d'un journal est prouvée par `dsh-remote-ctl`, qui
  emprunte exactement le même `RemoteClient`.
- **Tout essai sur iPhone réel** : voir le point 3 ci-dessus, qui est un préalable
  administratif et non technique.

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

./.build/debug/dsh-remote-ctl http://127.0.0.1:3080 sante
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> sessions 20
./.build/debug/dsh-remote-ctl http://<nom-magicdns-du-mac> journal <identifiant> 50
```

Le nom MagicDNS du Mac est celui que `tailscale status` affiche ; c'est aussi l'adresse
que `tailscale serve` publie.

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
├── DSHRemoteKit/        # bibliothèque partagée macOS + iOS
│   ├── Modeles.swift    # types du protocole, transport des enregistrements
│   ├── Evenements.swift # présentation des événements du journal
│   └── RemoteClient.swift
├── DSHRemoteCtl/        # tool de validation (macOS)
└── DSHRemoteApp/        # application SwiftUI (macOS + iOS)
    ├── AppDSHRemote.swift
    ├── ModeleApp.swift
    ├── Vues.swift
    └── VueJournal.swift
Tests/
└── DSHRemoteKitTests/   # décodage des charges utiles réelles
```

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

---

## Ce qui est prouvé

| Affirmation | Preuve |
|---|---|
| Le paquet compile pour macOS 14 et iOS 17 | `swift build` |
| Le protocole réel se décode | 4 tests verts sur des charges utiles copiées du serveur |
| Le bout en bout fonctionne | `dsh-remote-ctl <tailnet> sessions` liste 102 sessions avec titres, compteurs et dates |
| Le journal se lit | `dsh-remote-ctl <tailnet> journal <id> 8` affiche les enregistrements typés |
| Les refus sont respectés | `401` sans jeton, `403` avec `Origin`, `404` sur identifiant inconnu |
| L'application démarre sur macOS | processus vivant après 6 s, fenêtre 1100×720 présente |
| L'application fonctionne sur iOS | simulateur iPhone 17 Pro : 48 sessions vivantes affichées, connectées à la vraie instance |
| Le code compile pour un iPhone réel | `swift build --triple arm64-apple-ios18.0 --sdk <iphoneos>` |
| Xcode compile et lie pour iOS | `xcodebuild -destination 'generic/platform=iOS' build` → `BUILD SUCCEEDED` |
| Le projet Xcode produit une app installable | `DSHRemote.app` avec `Info.plist`, identifiant `org.example.DSHRemote`, installée et lancée dans le simulateur |
| Le simulateur ne lit pas le coffre du Mac | conteneur en bac à sable : l'app affiche « Aucun jeton d'appareil » |
| L'installation sur l'iPhone exige une action manuelle | `xcodebuild` échoue : appareil non enregistré, aucun profil pour `org.example.DSHRemote` |
| L'application est INSTALLÉE sur l'iPhone | `devicectl device info apps` liste `DSH Remote — org.example.DSHRemote — 0.1` |
| Elle est signée par l'équipe du propriétaire | `codesign -dv` : `TeamIdentifier=<equipe du proprietaire>`, `embedded.mobileprovision` présent |
| L'IP tailnet avec port ne sert RIEN | `http://100.101.102.103:3080` → `000` ; le nom MagicDNS → `200` |
