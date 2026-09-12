# dsh-remote-swift — client Swift multiplateforme

Client **Swift natif** (macOS et iOS) du plugin [`dsh-remote`](../../plugins/dsh-remote/).
Une seule bibliothèque partagée porte le protocole, le transport et les modèles ; les
deux applications la consomment telle quelle.

Ce paquet ne contient **aucune** interface pour l'instant : il livre la bibliothèque et
un tool de validation. L'application SwiftUI est le jalon 2 (voir la feuille de route du
[README du plugin](../../plugins/dsh-remote/#feuille-de-route)).

MISE À JOUR — le jalon 2 est écrit : voir [Application](#application) plus bas.

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
