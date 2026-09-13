# dsh-remote — surface JSON pour une application native

Ce plugin donne à une application **native** (Swift, macOS et iOS) une surface
JSON versionnée pour observer l'instance DSH qui tourne sur le Mac. Il ne
remplace pas l'interface web : il expose à un programme ce que l'interface web
ne sait dire qu'à un navigateur.

Compagnon Swift : [`packages/dsh-remote-swift`](../dsh-remote-swift/) — client
`DSHRemoteKit`, tool de validation `dsh-remote-ctl`, application SwiftUI **livrée**
(macOS et iOS ; voir la feuille de route en fin de document).

---

## Pourquoi ce plugin existe

Quatre constats **mesurés** sur cette installation (v0.1.5-rc.1), pas déduits de
la documentation. Chacun a commandé une décision d'architecture.

| Constat | Conséquence |
|---|---|
| DSH ne se lie qu'à la boucle locale ; `--host 0.0.0.0` est refusé au démarrage. | On ne touche pas au serveur : on lui **ajoute des routes**. |
| `tailscale serve` publie déjà l'instance sur le tailnet et relaie vers `127.0.0.1:3080`. | **Aucun port n'est ouvert, aucun serveur annexe n'est créé.** |
| Une route **nommée** (`webServer.register`) est dispatchée avant le repli de l'interface : elle n'est pas soumise à l'authentification navigateur. | C'est au plugin d'apporter la sienne. |
| `tailscale serve` termine la connexion et re-proxifie en boucle locale : `socket.remoteAddress` vaut **toujours** `127.0.0.1`, et l'en-tête `Tailscale-User-Login` est **falsifiable** par tout processus local. | Ni l'adresse source ni l'identité tailnet ne peuvent servir de contrôle d'accès. Seul un **secret partagé** le peut. |

Le quatrième point est le plus important, et il a été établi par falsification :
un `curl` local portant `Tailscale-User-Login: attaquant@exemple.fr` est accepté
tel quel par le serveur. Traiter cet en-tête comme une identité aurait été une
faille, pas une simplification.

---

## Chargement

Le plugin est un **module ES ordinaire**, chargé par le loader d'un profil : il
est donc **durable**, contrairement à un plugin dynamique posé par
`cordis_define`, qui disparaît au redémarrage.

Déclaration dans `~/.dsh/profiles/web/cordis.patch.yml` :

```yaml
- insert:
    - id: dsh-remote
      name: 'file:///<chemin-du-depot>/plugins/dsh-remote/dynamic/host.js'
      config:
        journaliser: true
```

### Ce que `patchReload: live` recharge — et ce qu'il ne recharge pas

Le profil déclare `patchReload: live`. Mesuré, et contre-intuitif :

| Changement | Effet |
|---|---|
| Ligne ajoutée, retirée ou désactivée dans `cordis.patch.yml` | **rechargé à chaud** — les routes apparaissent ou disparaissent en quelques secondes |
| **Code** de `dynamic/host.js` | **NON rechargé** |

Le rechargement à chaud porte sur la **configuration**, pas sur le module : Node met en
cache un module ESM par URL résolue, et Cordis réimporte la même URL. Une modification
de code exige donc un **redémarrage du processus**.

Ce n'est pas une précision gratuite : pendant le développement de ce plugin, trois
vérifications « à chaud » ont été crues bonnes alors que l'ancien code tournait encore.
Les routes répondaient — donc tout semblait en place — mais le comportement observé
était celui de la version précédente. **Toute modification de code doit être éprouvée
dans un processus neuf.**

---

## Les fichiers, et les tests

Le plugin est un **module ES**, chargé par le loader d'un profil : il peut donc
être découpé en plusieurs fichiers, contrairement à un plugin posé par
`cordis_define`.

| Fichier | Ce qu'il porte |
|---|---|
| `dynamic/host.js` | le plugin : les routes, le cache, le flux, le jeton |
| `dynamic/tailscale.js` | la découverte du tailnet — lancement du CLI local et **analyse pure** de sa sortie |
| `dynamic/journal.js` | la lecture d'un journal de session : trames zstd concaténées, lignes JSONL, résumé |
| `tests/tailscale.test.js` | les règles de la découverte, éprouvées sans lancer Tailscale |
| `tests/journal.test.js` | les règles de lecture du journal, éprouvées avec de vraies trames zstd |

```bash
node --test plugins/dsh-remote/tests/     # 15 tests, aucune dépendance
```

POURQUOI LE JOURNAL A DES TESTS, ET CE QU'ILS ONT ATTRAPÉ. Un journal DSH est une
**concaténation** de trames zstd, une par écriture — et `zstdDecompressSync` n'en
décode qu'une en s'arrêtant silencieusement. Une erreur de décodage ne lève donc
pas : elle rend un journal TRONQUÉ, et l'utilisateur croit avoir tout lu. Les
tests éprouvent cette concaténation, l'ignorance d'une ligne illisible (une
écriture interrompue n'est pas fatale), le résumé (premier en-tête, DERNIER
titre, plus grand `seq`) et le caractère **indicatif** du chemin déduit d'un nom
de dossier — `dsh-plugins` s'y relit `dsh/plugins`, et c'est pourquoi ce champ ne
sert jamais à lire : `cwd` fait foi.

DEUX CASSES D'EXTRACTION ONT ÉTÉ ATTRAPÉES, ET PAR DEUX MOYENS DIFFÉRENTS :

- `PLAFOND_DECOMPRESSION` était resté dans `host.js` alors que `decoderJournal`
  s'en sert — c'est le TEST qui l'a vu (`ReferenceError`) ;
- `cheminIndicatif` manquait à la liste d'import — c'est une INSTANCE NEUVE qui
  l'a vu : `/v1/sessions` répondait `500 listage impossible`.

Les deux auraient cassé chez l'utilisateur, dans le processus du harness. La
leçon est écrite dans le code : après une extraction, la liste des symboles
importés se vérifie **par grep**, pas de mémoire.

POURQUOI `node:test` ET PAS UNE DÉPENDANCE : la RÈGLE #0 fait de chaque
dépendance une surface d'attaque de plus dans un processus sans bac à sable. Le
runner est intégré à Node depuis la version 18 ; il n'y a rien à installer.

POURQUOI CES TESTS EXISTENT : le plugin n'en avait **aucun**, alors que c'est le
code qui s'exécute chez l'utilisateur, dans le processus du harness. Les règles
éprouvées sont celles qui décident de ce qu'on propose à l'utilisateur — seuls
les **Macs** sont proposés (un PC ou un iPhone ne peut pas héberger DSH), le point
final du DNS est retiré pour que le nom serve d'adresse, l'ordre est **stable**
(en ligne d'abord, puis par nom — la machine locale n'a aucune priorité), et les
deux diagnostics d'échec restent distincts : « sortie illisible » (le JSON lève)
n'est pas « sortie inattendue » (le JSON est valide, mais ce n'est pas un état de
tailnet).

`scripts/verifier.sh` les exécute, et le hook de pré-commit refuse un commit qui
les casse.

---

## Jeton d'appareil

Au premier chargement, le plugin tire 32 octets aléatoires, les stocke dans le
coffre du harness et **les affiche une seule fois** dans le terminal :

```
[dsh-remote] NOUVEAU JETON D APPAREIL (a saisir une fois dans l application, puis oublier) :
[dsh-remote] <43 caractères>
```

Le coffre est le service `credentials` du harness, qui persiste dans
`$DSH_HOME/.credentials.yaml` avec des permissions `0600` (vérifié).

Pour le lire depuis un autre outil du même utilisateur — c'est ce que fait
`dsh-remote-ctl` — la clé est `dsh-remote/device-token`. **Le jeton n'est jamais
renvoyé par une route HTTP**, pas même à un client authentifié : une route qui
rendrait le jeton serait un oracle.

Rotation : supprimer l'enregistrement du coffre, le plugin en crée un nouveau au
chargement suivant. Tous les appareils existants perdent l'accès.

---

## Protocole

Toutes les routes sont sous `/dsh-remote/v1/`. Le champ `protocole` est présent
dans **chaque** réponse : un client qui ne sait pas lire une version doit le
dire, pas deviner.

Authentification : `Authorization: Bearer <jeton>`. Jamais de jeton en paramètre
d'URL — un paramètre finit dans un journal d'accès ou un historique.

| Route | Méthode | Rôle |
|---|---|---|
| `/dsh-remote/v1/sante` | `GET` | Poignée de main : version du protocole, capacités. Aucune donnée. |
| `/dsh-remote/v1/sessions` | `GET`, `POST` | Liste des sessions, de la plus récente à la plus ancienne. |
| `/dsh-remote/v1/espaces` | `GET` | Espaces de travail du registre de l'hôte, **ceux sans session compris**, dans son ordre de création décroissante. |
| `/dsh-remote/v1/serveurs` | `GET` | Liste des Macs du tailnet, **découverte par l'hôte** — c'est ce qui donne une liste à l'iPhone. |
| `/dsh-remote/v1/session/<id>` | `POST` | Une page du journal d'une session. |
| `/dsh-remote/v1/session/<id>/prompt` | `POST` | Envoyer un prompt. Reprend la session si elle est froide. |
| `/dsh-remote/v1/session/<id>/annuler` | `POST` | Interrompre le tour en cours, **file d'attente conservée**. |
| `/dsh-remote/v1/flux` | `Upgrade` | WebSocket temps réel : une base, puis un message par écriture du journal. |

### `POST /v1/sessions`

```json
{ "limite": 50 }
```

### `POST /v1/session/<id>`

```json
{ "depuis": 0, "limite": 200, "types": ["user/message", "assistant/message"] }
```

### `POST /v1/session/<id>/prompt` — écrire

```json
{ "texte": "…", "mode": "queue", "requestId": "…", "fuseau": "Europe/Paris" }
```

`mode` vaut `queue` (par défaut, forme le prochain tour) ou `steer` (remis au pas
suivant du tour en cours). `requestId` et `fuseau` sont facultatifs.

Réponse `202` :

```json
{ "protocole": 1, "accepte": true, "mode": "queue", "requestId": "…", "reprise": false }
```

**`accepte` veut dire « l'hôte a pris le message »**, pas « le modèle a répondu » : la
réponse arrive par le journal ou par le flux, comme tout le reste.

**Une session froide n'est pas un refus.** L'hôte la résout ou la reprend lui-même — même
politique que l'interface web — et le dit dans `reprise`. Une session inconnue est `404`.

**`requestId` rend l'envoi IDEMPOTENT.** Rejouer la même demande avec le même identifiant
rend l'acceptation d'origine **sans insérer un second message**. C'est ce qui permet à un
client mobile de réessayer après une coupure réseau sans polluer la conversation ; sans
cela, une réponse perdue se paie par un doublon. L'identifiant est validé
(`^[A-Za-z0-9_-]{8,64}$`) et tiré par l'hôte s'il manque ou ne convient pas.

Le texte est borné à 200 000 caractères (`413` au-delà) et le corps de requête à 1 Mio.
Les refus portent un **code stable** et un statut qui distingue « réessayez » de « ça ne
marchera jamais » :

| Code | Statut | Sens |
|---|---|---|
| `gateway/bad-request`, `session/invalid-time-zone` | `400` | demande malformée |
| `session/not-found` | `404` | session inconnue |
| `session/model-unavailable`, `session/agent-busy`, `session/steer-unavailable` | `409` | état de la session, pas la demande |
| autre | `502` | échec côté harness |

### `POST /v1/session/<id>/annuler` — interrompre

```json
{ "protocole": 1, "annule": true }
```

Écrire depuis un téléphone, c'est souvent écrire pour **arrêter** ce qu'on a lancé. Sans
annulation, il faut revenir au Mac et la fonction perd son intérêt. L'annulation conserve
la file d'attente (`keepInbox`) : ce qui n'a pas encore été traité reste en attente. Une
session froide est refusée en `404` — il n'y a rien à interrompre.

### « Le service est absent de la composition » : une conclusion fausse, et pourquoi

Le jalon 4 est resté bloqué sur ce diagnostic : `ctx.get('sessionController')` rendait
`undefined`, et le service semblait donc absent. **Il ne l'était pas. Il était fourni trop
tard.**

Une sonde a mesuré ce que le contexte du plugin voit réellement, à trois instants :

| Instant | Services visibles | `sessionController` |
|---|---|---|
| À l'application du plugin | 6 (loader, chemins, arguments, arrêt) | absent |
| + 5 s | 65 (dont `agents`, `sessions`, `webServer`) | absent |
| + 15 s | 73 | **présent** |

Le plugin lisait le service **une seule fois, au chargement** — donc dans la première
ligne du tableau. Il figeait `undefined` pour toute la vie du processus. La composition
`web` charge ses entrées plusieurs secondes après les premières, et `sessionController`
arrive avec elles.

Ce que la mesure a coûté, et ce qu'elle a rapporté : deux hypothèses plausibles ont été
écartées (service non déclaré ; problème d'ordre d'activation résolu par `inject`), alors
que la vraie cause était une **capture précoce**, corrigée par une lecture paresseuse :

```js
const controleurEcriture = () => {
  const service = ctx.get('sessionController')   // relu À CHAQUE REQUÊTE
  return typeof service?.prompt === 'function' ? service : null
}
```

Règle retenue pour ce dépôt, en plus de « ne jamais tester `=== null` sur `ctx.get` » :
**un service lu dans `apply()` peut ne pas exister encore.** Le lire à l'usage, jamais à
l'installation.

### Une erreur avalée a coûté une heure de diagnostic

`ctx.get(…)` rend **`undefined`**, pas `null`, quand un service est absent. Le test
`controller === null` était donc faux, `undefined.prompt` levait, et le serveur web
convertissait l'exception en **`400` sans corps ni trace**. Depuis un client, cela
ressemble à une requête malformée — pas à un service manquant, qui était la vraie cause.

Toutes les routes convertissent maintenant leurs erreurs en réponses JSON explicites.
Règle retenue pour ce dépôt : **ne jamais tester `=== null` sur le résultat de
`ctx.get`** ; employer `typeof service?.membre !== 'function'`.

Le même piège s'est représenté sur l'annulation : `cancel()` **lève de façon synchrone**
quand la session n'est pas vivante. L'appeler en argument d'un `Promise.resolve(...)`
l'exécutait HORS de la chaîne, et l'exception ressortait de nouveau en `400` vide. Toute
lecture ou tout appel susceptible de lever doit être **dans** la chaîne :
`Promise.resolve().then(() => cancel(...))`.

### `Upgrade /v1/flux` — le flux temps réel

Le client ouvre le WebSocket (jeton en en-tête `Authorization`, **jamais** en paramètre
d'URL), puis envoie un premier message :

```json
{ "type": "demarrer", "session": "session-…", "depuisSeq": 1044 }
```

`depuisSeq` est facultatif, et c'est lui qui rend la **reprise non destructive** : le
serveur ne transmet que les enregistrements dont `seq` dépasse cette valeur. Une
reconnexion après coupure réseau ne renvoie donc pas ce que le client possède déjà.

Le serveur répond :

| Message | Contenu |
|---|---|
| `base` | Le résumé de la session, les derniers enregistrements, et `dernierSeq`. |
| `evenement` | Un enregistrement, dès qu'une écriture est détectée. |
| `delta` | Le nouveau `dernierSeq`, après un groupe d'évènements. |
| `tronque` | La fenêtre de lecture n'a pas suffi : le client doit redemander une page. |
| `erreur` | Un message lisible, jamais une trace technique. |

Le serveur sonde le fichier toutes les **750 ms** et ne décompresse que les **derniers
64 Kio**, fenêtre qu'il élargit jusqu'à 8 Mio si nécessaire. Relire le journal entier à
chaque tour ferait croître le coût sans fin sur une session longue ; comme un journal
est append-only, tout ce qui précède la fin est déjà connu du client.

Boucle de vie : un `ping` toutes les 30 s, et une fermeture `1008` si le client n'absorbe
pas ses messages (4 Mio en attente) — un client lent ne doit pas faire enfler la mémoire
du harness. Il se reconnecte avec `depuisSeq` et rattrape sans perte.

`depuis` et `limite` paginent les enregistrements **filtrés**. `types` restreint
aux types demandés. Sans `types`, les enregistrements volumineux
(`request/header`, `request/context`, `system/message`,
`session/title-llm-request`) sont **exclus** : ce sont les plus gros du journal et
rarement ce qu'un client veut afficher.

### Modèle de session

```json
{
  "id": "session-83727ed7-…",
  "titre": "Application iOS Swift pour DeepSeek",
  "cwd": "/chemin/du/projet",
  "preset": "standard",
  "creeLe": 1789059396815,
  "dernierEvenementLe": 1789220160414,
  "dernierSeq": 454,
  "nbEnregistrements": 456,
  "vivante": true,
  "octets": 425393,
  "projet": "--chemin-du-projet-encode--",
  "cwdIndicatif": "/chemin/du/projet/indicatif//",
  "attendReponse": false
}
```

Trois avertissements sur ces champs :

- **`vivante` ne veut PAS dire « active ».** Le champ indique que DSH garde la
  session chargée dans le processus — donc reprenable instantanément — et non
  qu'un tour s'y exécute. Mesuré sur une installation réelle : dix sessions
  étaient marquées vivantes, dont sept dont le dernier évènement datait de la
  minute du démarrage du harness. C'est le comportement normal après une journée
  de travail, mais l'étiquette « vivantes » le faisait passer pour une anomalie.
  Pour l'activité réelle, lire **`statut`**.
- **`statut` vaut `null` quand la session n'est pas ouverte dans ce processus.**
  `null` signifie « état inconnu », à ne pas confondre avec `inactif`. Quand il
  est renseigné, il vaut `en_cours` (un tour s'exécute) ou `inactif`.

- **`cwdIndicatif` n'est pas fiable.** DSH encode `/chemin/projet-externe` en
  `--Users-x-dsh-plugins--` en remplaçant chaque `/` par `-` : le tiret de
  `dsh-plugins` est indiscernable d'un séparateur. Ce champ n'existe que pour
  donner un libellé avant la lecture du journal. **`cwd` fait foi**, et il vient
  du journal lui-même.
- `vivante` signifie « le harness connaît encore cette session dans ce
  processus ». Une session ancienne est `false` ; elle reste lisible.
- **`attendReponse` dit qu'une DÉCISION humaine est attendue** — une question d'un
  tool (`ask_user`) ou une autorisation. C'est l'information la plus actionnable de
  la liste : une session dans cet état ne repartira pas toute seule. `false` est la
  réponse normale, et le champ est **absent** d'un hôte plus ancien, ce qui veut
  dire « ne sait pas » et non « non ».

---

## « L'agent attend une réponse » : observer sans répondre

Une session peut être bloquée sur une décision de l'utilisateur — le modèle a posé une
question, ou un tool demande une autorisation. C'est le seul état de la liste qui
n'avance **jamais** tout seul, et donc celui qu'un téléphone doit signaler.

**Ce plugin n'y répond pas**, et ne le prétend pas : le harness n'admet qu'un répondeur
terminal par déploiement, et l'interface web l'occupe. Mais il peut le **dire**, en
s'inscrivant sur les deux waterfalls concernés (`user-questions/request` et
`approval/request`) pour compter les demandes en cours, puis en les relâchant.

La durée de l'attente n'est pas devinée : le listener **traverse** la promesse du
waterfall (`next()`), donc il voit le moment exact où la question est résolue — répondue,
refusée ou abandonnée. Un compteur par session, parce que deux demandes peuvent se
superposer.

### Le piège : dans un waterfall, un observateur placé après le répondeur ne voit RIEN

Trois mesures ont été nécessaires, et chacune a écarté une explication plausible :

| Hypothèse | Mesure | Verdict |
|---|---|---|
| Le service n'existe pas / mauvaise portée | l'évènement arrive bien à la racine comme dans un plugin | écartée |
| Il faut `{ global: true }` pour franchir le filtre de portée | posé, l'observateur ne voit toujours rien | écartée |
| L'inscription est trop tardive | une sonde inscrite 8 s après le démarrage ne voit rien non plus | écartée… |

La cause est ailleurs, et elle est structurelle : `ctx.waterfall` construit une chaîne
d'écouteurs et **s'arrête au premier qui ne rappelle pas `next()`**. Le répondeur, lui,
répond — il ne rappelle donc pas `next`. Un observateur inscrit après lui n'est **jamais
appelé**, quel que soit son contexte. Mesuré : 4 écouteurs inscrits sur l'évènement, dont
le nôtre, et le nôtre jamais atteint.

D'où l'inscription en tête :

```js
ctx.on(evenement, (requete, next) => {
  marquer(requete.agent)                 // on note l'attente
  return Promise.resolve(next()).finally(() => relacher(requete.agent))
}, { prepend: true })                    // AVANT le répondeur, sinon jamais appelé
```

`{ global: true }` n'est **pas** nécessaire : un écouteur non étiqueté est admis par le
filtre de portée. Seule la place dans la chaîne comptait.

---

## Espaces de travail : le registre de l'hôte, pas une déduction

L'application groupait ses sessions par `cwd` et en déduisait ses espaces. Deux
conséquences, toutes deux visibles à l'écran :

- **un espace sans session était invisible.** Un espace s'enregistre dès qu'on choisit
  un dossier, avant qu'une session y soit ouverte ; l'interface web l'affiche, pas
  l'application ;
- **l'appartenance d'une session était devinée** par comparaison de chemins — ce qui se
  trompe sur un dossier renommé, deux projets homonymes, ou une session de sous-agent.

`GET /v1/espaces` publie donc le registre tel quel :

```json
{
  "protocole": 1,
  "espaces": [
    { "id": "…", "titre": "dsh-plugins", "chemin": "/Users/…/dsh-plugins",
      "creeLe": 1789059396739, "sessions": ["session-…", "session-…"] },
    { "id": "…", "titre": "veille", "chemin": "/Users/…/veille",
      "creeLe": 1788445270539, "sessions": [] }
  ]
}
```

- **`sessions` est l'appartenance**, un fait du registre : le client ne la recalcule pas.
- **L'ordre est celui du registre** — création décroissante (`newestAt`) — et il est
  conservé tel quel. Retrier côté plugin ferait diverger l'application du web à la
  première évolution de la règle.
- **`creeLe` est en millisecondes epoch**, comme partout ailleurs dans ce protocole.

`capacites.espaces` annonce la disponibilité de la route : un client qui lit `false`
(hôte plus ancien, ou service absent) garde son regroupement par `cwd` au lieu d'attendre
une liste qui ne viendra jamais. Le service est lu **à chaque requête** :
`workspaceRegistry` est publié par vagues, comme `sessionController`.

---

## Découverte des serveurs : le Mac découvre, l'iPhone consomme

Personne ne devrait avoir à taper `http://<machine>.<tailnet>.ts.net` pour choisir un
serveur. Encore faut-il pouvoir **découvrir** la liste des machines — et c'est
précisément ce qu'un iPhone ne peut pas faire : iOS interdit à une application
d'exécuter un processus, et le socket LocalAPI de l'application Tailscale n'est pas
lisible depuis un autre bac à sable.

L'instance DSH, elle, tourne sur un Mac qui a Tailscale. C'est donc **l'hôte qui
découvre**, et l'application qui **lit** le résultat par une route authentifiée.

### `GET /v1/serveurs`

```json
{
  "protocole": 1,
  "serveurs": [
    { "nom": "MacMini", "nomDNS": "macmini.exemple.ts.net", "enLigne": true, "local": true },
    { "nom": "Portable Deux", "nomDNS": "portable-deux.exemple.ts.net", "enLigne": false, "local": false }
  ],
  "diagnostic": null
}
```

- `nomDNS` est le nom MagicDNS **sans point final** : l'adresse en découle
  (`http://<nomDNS>`, port 80 — la convention que `tailscale serve` publie), et le
  client n'a rien à recalculer.
- `local` marque la machine qui a répondu. C'est une information que **seul l'hôte**
  peut donner : sur iPhone, l'appareil qui interroge n'est évidemment pas celui qui
  répond.
- `diagnostic` n'est renseigné que lorsque la liste est vide, et il dit **pourquoi** :
  binaire introuvable, Tailscale muet, délai dépassé, aucun Mac dans le tailnet. Quatre
  causes qui ne se corrigent pas de la même façon. Une liste vide sans raison est
  indébogable.
- Seules les machines **macOS** sont retenues. Proposer un PC Windows ou un iPhone comme
  serveur DSH serait une promesse que l'installation ne peut pas tenir.

### Ce qui a été mesuré, et qui a coûté du temps

`tailscale status --json` ne dépend pas seulement du binaire, mais du **chemin employé
pour le lancer** :

| Chemin | Résultat |
|---|---|
| `/usr/local/bin/tailscale` (lien symbolique vers le binaire de l'application) | **échec** — « The current bundleIdentifier is unknown to the registry » |
| `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (chemin direct) | `200` — l'état complet du tailnet |
| `~/.local/bin/tailscale` (lanceur de l'application) | `200` |

Un lien symbolique fait perdre au CLI l'identité de bundle dont il a besoin pour
joindre l'application Tailscale. Le plugin essaie donc ses candidats **jusqu'à un
succès**, et non jusqu'au premier fichier exécutable — c'est la différence entre une
liste qui se remplit et une liste qui reste vide sans explication.

Aucun binaire n'est mémorisé côté plugin : chaque découverte fraîche refait l'essai dans
l'ordre et s'arrête au premier qui répond. Le coût est de quelques dizaines de
millisecondes, payé au plus une fois par période de cache. (Côté Swift, le binaire qui a
répondu *est* retenu — les deux implémentations ne se comportent pas pareil, et c'est
écrit ici pour que personne ne s'étonne de la différence.)

### Ce que cette route ne fait pas

- **Aucune entrée n'entre dans la ligne de commande** : l'argv est fixe
  (`status --json`), et `execFile` ne passe **jamais** par un shell. Il n'y a donc pas
  de surface d'injection, même si un jour un paramètre était ajouté.
- **Rien n'est exécuté avant l'authentification** : `autoriser` est appelé en premier,
  et une requête refusée ne lance aucun processus.
- **Aucun scan réseau, aucune requête sortante** : on lit l'état LOCAL d'un Tailscale
  déjà en place. Le plugin n'émet aucun paquet.
- **Coût borné** : délai de 8 s, sortie plafonnée à 4 Mio, résultat mis en cache 15 s
  (un tailnet ne change pas d'une seconde à l'autre). **Le cache n'est pas un verrou** :
  deux requêtes simultanées à cache froid lancent chacune son processus. Le cache limite
  la fréquence, il ne sérialise pas — le dire autrement serait une affirmation non
  mesurée.
- **Aucun chemin absolu publié** : le diagnostic ne contient qu'une ligne courte, jamais
  le chemin d'un binaire.
- **Le code de sortie ne sert pas de preuve.** Un CLI qui n'a pas pu joindre Tailscale
  écrit son erreur sur **stdout** en sortant avec le code **0** — mesuré depuis une
  application macOS ouverte par le Finder : `The Tailscale GUI failed to start: …`, code 0.
  La route exige donc un **JSON analysable** ; sinon elle garde la raison du CLI et essaie
  le candidat suivant. Se fier au code de sortie ferait conclure « tailnet vide » alors
  que le tailnet va bien — et arrêterait la boucle avant le lanceur qui, lui, répond.

### Limites assumées

- La liste vient de l'état Tailscale **de la machine qui exécute le harness**. Si
  Tailscale n'y est pas installé ou n'est pas connecté, la route rend une liste vide
  avec sa raison — le reste du plugin fonctionne normalement.
- L'adresse déduite suppose la convention `tailscale serve` sur le **port 80** du nom
  MagicDNS. Une publication sur un autre port demanderait un champ supplémentaire, qui
  n'existe pas tant qu'aucun cas réel ne l'exige.
- La découverte ne dit pas si un Mac donné **sert réellement** une instance DSH : elle
  dit qu'il est sur le tailnet et en ligne. Le client le vérifie en s'y connectant.

---

## Lecture des journaux : le point délicat

Un journal de session (`session.v3.jsonl.zstd`) est une **concaténation de
trames zstd indépendantes**, une par écriture. Sur un journal réel de cette
installation : **169 trames** pour 891 Ko décompressés.

`zlib.zstdDecompressSync` n'en décode **qu'une seule** et s'arrête
silencieusement — il rend 215 octets et ne signale aucune erreur. L'utiliser seul
ne montrerait que la première écriture du journal, ce qui donnerait un affichage
tronqué sans le moindre signe d'échec.

Le plugin avance donc trame par trame, en trouvant la fin de chacune par
recherche binaire (une tranche qui décode n'est pas forcément exactement une
trame : zstd ignore ce qui suit). Mesuré : **172 trames, 914 Ko, 62 ms**.

Bornes : 64 Mio décompressés par journal, 512 Mio par fichier. Un journal qui
dépasse est refusé en `413`, jamais tronqué en silence.

Un cache mémoire (clé : chemin) évite de redécoder un journal inchangé ; il est
invalidé par couple `(taille, mtime)`.

---

## Sécurité — dérogations assumées à la RÈGLE #0

La RÈGLE #0 d'[`AGENTS.md`](../../AGENTS.md) interdit huit choses. Ce plugin en
déroge sur **un** point, délibéré et documenté ici.

### Il affiche un identifiant porteur (interdit #3)

À sa création, le jeton est écrit **en clair dans le terminal**. C'est le seul
canal d'amorçage disponible : l'application iPhone n'a aucun autre moyen
d'apprendre le secret, et une route qui le rendrait serait pire.

**Risque** : une capture d'écran de ce terminal, ou un enregistrement de session,
donne le contrôle de la surface de lecture. **Garde-fous** : le jeton est affiché
une seule fois ; il n'est jamais journalisé par `tracer` (qui ne trace que
méthode, route, code et compteur) ; il n'est jamais renvoyé par une route ; le
coffre est en `0600`.

### Le jeton autorise désormais l'ÉCRITURE (portée accrue)

Tant que le jeton n'ouvrait que la lecture, le perdre exposait les journaux de
session. Depuis que `/prompt` et `/annuler` fonctionnent, **le même jeton fait
écrire dans les sessions** : envoyer un message au nom de l'utilisateur, ou
interrompre un travail en cours. La portée du secret a changé, pas sa forme.

Ce n'est pas une dérogation de plus, c'est la conséquence assumée de la fonction :
une application qui ne peut pas répondre à l'agent n'a pas d'intérêt. Trois
conséquences pratiques :

- le jeton se traite comme une clé de contrôle du harness, pas comme une clé de
  lecture. Il n'est **jamais** recopié hors du coffre et du trousseau du client ;
- une révocation existe (`supprimer l'enregistrement du coffre`) mais elle est
  **globale** — il n'y a pas de révocation par appareil ;
- les approbations restent **inaccessibles** (voir les limites) : écrire un
  prompt n'autorise pas à répondre à une demande de permission. La portée est
  réelle, elle est bornée.

### Ce que le plugin ne fait PAS

- **Aucune surface réseau nouvelle** : les routes vivent sur le serveur DSH
  existant. Aucun `listen`, aucun port, aucun serveur annexe.
- **Aucune donnée de session journalisée** : `tracer` écrit méthode, chemin sans
  paramètre, code HTTP et compteur. Jamais un contenu, jamais un chemin local,
  jamais un jeton.
- **Aucun `Origin` toléré** : refusé en `403` **avant** le test du jeton. Un
  client natif n'en envoie jamais, un navigateur en envoie toujours — c'est la
  barrière anti-CSRF et anti-DNS-rebinding.
- **Comparaison à temps constant** (`timingSafeEqual`), longueurs égalisées au
  préalable pour ne pas fuiter la taille du secret.
- **Aucune E/S avant authentification** : une requête refusée ne lit ni le
  disque ni le coffre, et reçoit une réponse fixe.
- **Zéro dépendance tierce** : le WebSocket est écrit à la main (une centaine de
  lignes) plutôt que d'ajouter un paquet dans un processus sans bac à sable.
- **Aucune traversée de chemin** : l'identifiant de session est validé par
  `^[A-Za-z0-9_-]{1,128}$` avant toute construction de chemin.
- **Aucun contenu de prompt journalisé** : `tracer` écrit la route, le mode retenu
  et le NOMBRE de caractères. Jamais le texte — il peut contenir ce que
  l'utilisateur ne veut pas voir recopié dans un terminal.
- **Écriture bornée** : texte limité à 200 000 caractères, corps de requête à
  1 Mio, identifiant d'envoi validé par une forme stricte.

---

## API internes utilisées

Aucune n'offre de garantie de stabilité. Chacune est lue par `ctx.get(...)` puis
testée, et le plugin se dégrade au lieu de lever une exception au chargement.

| API | Usage | Si elle disparaît |
|---|---|---|
| `webServer.register` / `.registerUpgrade` | enregistrer routes et flux | sans `webServer`, le plugin journalise l'échec et ne s'active pas |
| `credentials.readRecord` / `.modifyRecord` | stocker le jeton | sans coffre, aucune authentification n'est possible : toutes les routes répondent `401` |
| `sessions.get`, `agents.roots` | marquer une session `vivante` | `vivante` vaut `false` partout ; le reste fonctionne |
| `sessionController.prompt` / `.cancel` | écrire et interrompre | `capacites.ecriture` vaut `false`, la lecture continue de fonctionner, les deux routes répondent `503` |
| `workspaceRegistry.list()` | publier les espaces de travail, **vides compris** | `capacites.espaces` vaut `false` et `/v1/espaces` répond `503` ; le client retombe sur le regroupement des sessions par `cwd` |
| `ctx.on('user-questions/request' \| 'approval/request', …, { prepend: true })` | signaler qu'une décision humaine est attendue | `attendReponse` reste `false` partout : l'indicateur disparaît, rien d'autre ne casse |
| `ctx.effect` | retirer les routes au déchargement | les routes fuient jusqu'au redémarrage |

**`sessionController` est relu à chaque requête, jamais au chargement** : la
composition `web` le fournit une dizaine de secondes après le démarrage. Une
lecture unique dans `apply()` le manquerait à jamais — c'est l'erreur qui a fait
croire à son absence (voir plus haut). `capacites.ecriture` répond donc `true`
seulement une fois le service réellement là, et un client qui lit `false` doit
continuer à proposer la lecture seule plutôt que d'attendre.

Formes d'enregistrement du journal (`session`, `session/title`, `user/message`,
`assistant/message`, `tool/call`, `tool/result`, `step/start`, `step/end`,
`turn/start`, `permission/preset`, `sandbox/mode`, `approval/policy`…) : le
plugin ne les interprète **pas**. Il les transporte. Seuls `type`, `seq`, `time`
et l'en-tête `session` sont lus — le reste traverse sans être compris, ce qui
limite la surface de casse.

---

## Ce qui a été prouvé, et comment

| Affirmation | Preuve |
|---|---|
| Une route nommée échappe à l'authentification navigateur | `200` sans cookie sur `/dsh-remote-probe/ping` (sonde), là où `/` répond `401` |
| Le tailnet atteint la route | `200` via le nom MagicDNS du Mac (`tailscale serve`) |
| L'hôte publie la liste du tailnet | instance neuve : `GET /v1/serveurs` → 3 Macs, `local: true` sur celui qui répond, et **NI** le PC Windows **NI** l'iPhone |
| L'hôte publie ses espaces de travail | instance neuve : `GET /v1/espaces` → 7 espaces, du plus récent au plus ancien (`creeLe` décroissant), avec l'appartenance des sessions |
| La découverte ne lit rien avant l'authentification | sur cette route : `401` sans jeton, `403` avec `Origin`, `405` en `POST` |
| Le CHEMIN du binaire décide du succès | `/usr/local/bin/tailscale` (lien symbolique) échoue « The current bundleIdentifier is unknown to the registry » ; `/Applications/Tailscale.app/Contents/MacOS/Tailscale` rend l'état complet |
| La capacité est annoncée | `capacites.decouverte: true` dans `/v1/sante` |
| L'iPhone CONSOMME la découverte | simulateur iPhone 17 Pro : les 3 Macs s'affichent avec icône et état, « hôte interrogé » sur la machine qui répond |
| Le WebSocket traverse `tailscale serve` | `101 Switching Protocols` + trame reçue, via le tailnet |
| La CONFIGURATION se recharge à chaud | route en `404` après désactivation de la ligne, `401` après réactivation, sans redémarrage |
| Le CODE exige un redémarrage | après modification du fichier et rechargement de la configuration, l'ancien code répondait encore |
| Le flux pousse de vrais évènements | instance neuve : `base=1`, `evenement=5`, `delta=3`, 0 doublon, ordre croissant, pendant que la session écrivait |
| La reprise ne renvoie rien de connu | reconnexion avec `depuisSeq` = dernier seq : 0 évènement déjà connu |
| Le service d'écriture est ABSENT au chargement du plugin | sonde : 6 services visibles à l'application du plugin, `sessionController` absent ; présent à `T+15 s` (73 services) |
| Le service d'écriture est LÀ à l'usage | `capacites.ecriture: true`, et un prompt adressé à une session FROIDE est accepté (`202`) |
| La session froide est REPRISE | réponse `{"accepte":true,"reprise":true}`, puis `turn/start` → `user/message` → `assistant/message` → `turn/end` dans le journal |
| L'envoi est IDEMPOTENT | même `requestId` rejoué : `202` + `accepte:true`, et **une seule** occurrence du message dans le journal (24 enregistrements avant et après) |
| Les refus sont typés et traduisibles | `texte vide` → `400`, session inconnue → `404` `session/not-found`, fuseau invalide → `400` `session/invalid-time-zone` |
| L'annulation fonctionne | session froide → `404` ; tour vivant → `202 {"annule":true}` |
| Le prompt respecte la barrière d'accès | `401` sans jeton, `403` avec `Origin`, sur la route d'écriture comme sur les autres |
| L'écriture fonctionne depuis Swift | `dsh-remote-ctl <adresse> prompt <id> "…"` → `accepté: true` ; essai d'intégration `swift test --filter ecritureReelle` vert contre un hôte réel |
| L'attente d'une décision est SIGNALÉE | `ask_user` déclenché pour de vrai : `attendReponse: true` tant que la question est en attente, `false` après la réponse (les deux fronts mesurés) |
| La capacité est annoncée séparément | `capacites.questions: true`, distinct de `capacites.approbations: false` — signaler n'est pas répondre |
| L'observateur doit être EN TÊTE | 4 écouteurs inscrits sur le waterfall, le nôtre jamais atteint avant `{ prepend: true }` |
| Le flux fonctionne depuis Swift | `dsh-remote-ctl <adresse> flux <id>` : 5 évènements et 3 deltas reçus en direct, 0 doublon, curseur conservé |
| Sans jeton : refus | `401` sur `/v1/sante` et sur l'`Upgrade` WebSocket |
| Avec `Origin` : refus | `403` |
| L'identité tailnet est falsifiable | `curl` local avec `Tailscale-User-Login: attaquant@exemple.fr` → accepté |
| Le jeton est stocké en `0600` | permissions lues sur `~/.dsh/.credentials.yaml` |
| Traversée de chemin refusée | `POST /v1/session/..%2f..%2fetc%2fpasswd` → `404` |
| Identifiant inconnu refusé | `404` |
| Le journal se décode entièrement | 172 trames, 914 Ko, 62 ms, **0 ligne illisible** |
| Le client Swift lit réellement les données | `dsh-remote-ctl <tailnet> sessions 6` affiche 486 évts et une date sur la session courante |

Un bug réel a été trouvé par cette méthode : le client Swift attendait du
`snake_case` quand le plugin émet du `camelCase`. Les tests Swift « passaient »
parce qu'ils avaient été écrits contre la même hypothèse fausse ; c'est la
comparaison avec la charge utile réelle qui l'a révélé. Les tests vérifient
désormais explicitement `nbEnregistrements` et `dernierEvenementLe`.

---

## Limites connues

- **L'écriture est opérationnelle, avec une portée à connaître** : envoyer un prompt
  et interrompre un tour. Le jeton d'appareil autorise donc **l'écriture**, pas
  seulement la lecture (voir « Sécurité »).
- **Les questions et les autorisations sont SIGNALÉES, jamais résolues.** Le plugin
  annonce qu'une décision est attendue (`attendReponse`) sans permettre d'y répondre :
  le harness n'admet qu'un répondeur terminal par déploiement, et l'interface web
  l'occupe. Un prompt peut donc être envoyé pendant qu'un tool attend une réponse, mais
  la réponse se donne sur le Mac.
- **Les approbations ne sont pas exposées, par conception.** Le seam d'approbation de
  DSH n'admet **qu'un répondeur terminal par déploiement**, et l'interface web occupe
  déjà cette place : répondre depuis l'iPhone exigerait de la lui retirer. Toute
  implémentation future devra donc choisir explicitement quel répondeur sert les
  approbations, ou composer les deux — ce n'est pas un ajout anodin.
- **Aucun envoi de fichier ni d'image.** L'hôte sait recevoir des pièces jointes
  (`sessionController.prompt` les accepte), mais les téléverser depuis le client
  exigerait une route de dépôt et un quota : hors périmètre.
- **La file d'attente n'est pas exposée** : un prompt `queue` s'ajoute, mais la
  liste de ce qui attend, sa réorganisation et son retrait ne sont pas lisibles
  depuis le plugin.
- **Le flux interroge le disque, il n'écoute pas le bus d'évènements interne du
  harness.** La latence est donc celle de l'intervalle de scrutation (750 ms). En
  contrepartie, il suit aussi les sessions écrites par un AUTRE processus — ce que
  ne permettrait pas un abonnement interne.
- **Modifier le code du flux exige un redémarrage du harness** (voir « Ce que
  `patchReload: live` recharge »).
- **Aucune révocation par appareil.** Le jeton est unique : le tourner révoque
  tout le monde.
- **Le jeton est propre à CHAQUE HÔTE.** Il est tiré au premier chargement du plugin et
  rangé dans le coffre de la machine — deux Macs qui hébergent le plugin ont donc deux
  jetons distincts. Un client qui interroge plusieurs machines doit détenir celui de
  l'hôte qu'il vise : le sien ne vaut pas pour les autres. C'est une propriété du
  dispositif, pas un défaut à corriger ici — partager un jeton entre machines est un
  choix, qui se fait en recopiant l'enregistrement du coffre, et il élargit la portée du
  secret à toutes les machines qui le portent.
- **`vivante` n'est pas une preuve d'activité.** Une session reprise par un autre
  processus peut être marquée vivante à tort ; le champ dit seulement ce que CE
  processus connaît.
- **Le cache est par processus** et n'est pas partagé entre instances de DSH.
- **Un journal en cours d'écriture peut être lu partiellement** : la dernière
  trame incomplète est ignorée et `tronque: true` est renvoyé.

---

## Feuille de route

| Jalon | Contenu | État |
|---|---|---|
| 1 | Plugin, protocole, jeton, lecture des journaux, tool Swift de validation | **livré et prouvé** |
| 2 | Application SwiftUI lecture seule, macOS puis iOS | **livré et connecté** — 106 sessions affichées sur l'iPhone réel via Tailscale |
| 3 | Flux temps réel des événements (`/v1/flux`) | **livré et prouvé** (plugin, client Swift et application) |
| 4 | Écriture : prompt, approbations, questions | **prompt, annulation et SIGNALEMENT d'une décision attendue livrés et prouvés** ; le « blocage » était une capture précoce du service, corrigée. Répondre aux questions et aux approbations reste hors d'atteinte : un seul répondeur terminal par déploiement, déjà occupé par l'interface web |
| 5 | Installation et signature iOS | **livré** — app signée et installée sur l'iPhone du propriétaire, connectée au harness via Tailscale (106 sessions) |
