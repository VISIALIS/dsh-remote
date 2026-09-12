# dsh-remote — surface JSON pour une application native

Ce plugin donne à une application **native** (Swift, macOS et iOS) une surface
JSON versionnée pour observer l'instance DSH qui tourne sur le Mac. Il ne
remplace pas l'interface web : il expose à un programme ce que l'interface web
ne sait dire qu'à un navigateur.

Compagnon Swift : [`packages/dsh-remote-swift`](../dsh-remote-swift/) — client
`DSHRemoteKit`, tool de validation `dsh-remote-ctl`, application SwiftUI (jalon 2,
pas encore écrite).

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
| `/dsh-remote/v1/session/<id>` | `POST` | Une page du journal d'une session. |
| `/dsh-remote/v1/flux` | `Upgrade` | WebSocket temps réel : une base, puis un message par écriture du journal. |

### `POST /v1/sessions`

```json
{ "limite": 50 }
```

### `POST /v1/session/<id>`

```json
{ "depuis": 0, "limite": 200, "types": ["user/message", "assistant/message"] }
```

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
  "cwdIndicatif": "/chemin/du/projet/indicatif//"
}
```

Deux avertissements sur ces champs :

- **`cwdIndicatif` n'est pas fiable.** DSH encode `/chemin/projet-externe` en
  `--Users-x-dsh-plugins--` en remplaçant chaque `/` par `-` : le tiret de
  `dsh-plugins` est indiscernable d'un séparateur. Ce champ n'existe que pour
  donner un libellé avant la lecture du journal. **`cwd` fait foi**, et il vient
  du journal lui-même.
- `vivante` signifie « le harness connaît encore cette session dans ce
  processus ». Une session ancienne est `false` ; elle reste lisible.

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

---

## API internes utilisées

Aucune n'offre de garantie de stabilité. Chacune est lue par `ctx.get(...)` puis
testée, et le plugin se dégrade au lieu de lever une exception au chargement.

| API | Usage | Si elle disparaît |
|---|---|---|
| `webServer.register` / `.registerUpgrade` | enregistrer routes et flux | sans `webServer`, le plugin journalise l'échec et ne s'active pas |
| `credentials.readRecord` / `.modifyRecord` | stocker le jeton | sans coffre, aucune authentification n'est possible : toutes les routes répondent `401` |
| `sessions.get`, `agents.roots` | marquer une session `vivante` | `vivante` vaut `false` partout ; le reste fonctionne |
| `ctx.effect` | retirer les routes au déchargement | les routes fuient jusqu'au redémarrage |

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
| Le WebSocket traverse `tailscale serve` | `101 Switching Protocols` + trame reçue, via le tailnet |
| La CONFIGURATION se recharge à chaud | route en `404` après désactivation de la ligne, `401` après réactivation, sans redémarrage |
| Le CODE exige un redémarrage | après modification du fichier et rechargement de la configuration, l'ancien code répondait encore |
| Le flux pousse de vrais évènements | instance neuve : `base=1`, `evenement=5`, `delta=3`, 0 doublon, ordre croissant, pendant que la session écrivait |
| La reprise ne renvoie rien de connu | reconnexion avec `depuisSeq` = dernier seq : 0 évènement déjà connu |
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

- **Lecture seule.** `capacites.ecriture` et `capacites.approbations` valent
  `false`. Envoyer un prompt, répondre à une approbation ou à une question n'est
  pas implémenté (jalon 4).
- **Le flux interroge le disque, il n'écoute pas le bus d'évènements interne du
  harness.** La latence est donc celle de l'intervalle de scrutation (750 ms). En
  contrepartie, il suit aussi les sessions écrites par un AUTRE processus — ce que
  ne permettrait pas un abonnement interne.
- **Modifier le code du flux exige un redémarrage du harness** (voir « Ce que
  `patchReload: live` recharge »).
- **Aucune révocation par appareil.** Le jeton est unique : le tourner révoque
  tout le monde.
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
| 2 | Application SwiftUI lecture seule, macOS puis iOS | à faire |
| 3 | Flux temps réel des événements (`/v1/flux`) | à faire |
| 4 | Écriture : prompt, approbations, questions | à faire |
| 5 | Installation et signature iOS (compte développeur, 7 jours sans) | à faire |
