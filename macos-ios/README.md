# dsh-remote-swift — client Swift multiplateforme

Client **Swift natif** (macOS et iOS) du plugin [`dsh-remote`](../../plugins/dsh-remote/).
Une seule bibliothèque partagée porte le protocole, le transport et les modèles ; les
deux applications la consomment telle quelle.

Ce paquet ne contient **aucune** interface pour l'instant : il livre la bibliothèque et
un tool de validation. L'application SwiftUI est le jalon 2 (voir la feuille de route du
[README du plugin](../../plugins/dsh-remote/#feuille-de-route)).

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
│   ├── Modeles.swift    # types du protocole, erreurs explicites
│   └── RemoteClient.swift
└── DSHRemoteCtl/        # tool de validation (macOS)
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
