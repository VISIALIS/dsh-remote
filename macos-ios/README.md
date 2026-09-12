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

Il faut donc une **cible d'application Xcode** (`com.apple.product-type.application`)
consommant `DSHRemoteKit` comme dépendance de paquet local. Le simulateur, lui,
fonctionne déjà : un `.app` assemblé à la main et signé ad hoc s'y installe et s'y
lance (voir plus haut).

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
| Xcode ne produit PAS d'app installable | aucun `.app` dans `Build/Products/Debug-iphoneos`, seulement un binaire nu |
