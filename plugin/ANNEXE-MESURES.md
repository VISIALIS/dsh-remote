# dsh-remote — annexe : carnets de mesures

**Ce fichier est l'annexe de [`README.md`](README.md).** Il ne fait pas partie du
contrat : il raconte comment chaque règle est née — un défaut observé, la mesure qui
l'a établi, et le remède. Le contrat, la procédure et les limites ouvertes sont dans le
README ; en cas de doute, c'est le contrat qui tranche, et si le code dit autre chose,
c'est un défaut, pas une interprétation.

**POURQUOI CES RÉCITS EXISTENT, ET POURQUOI ILS SONT ICI.** Un dépôt dont la
documentation oublie POURQUOI une règle existe finit par la voir « simplifiée » par
quelqu'un de bonne foi — et le défaut revient. La valeur de ces récits est réelle ; leur
place est simplement à côté du contrat, pas dedans : le README se lit maintenant d'un
bout à l'autre sans traverser une investigation, et chaque section déplacée y laisse un
renvoi.

**CE QU'ON Y TROUVE** — neuf carnets, puis le tableau des preuves :

| Carnet | Ce qu'il établit |
|---|---|
| `Pourquoi ce plugin existe` | les quatre constats **mesurés** qui commandent l'architecture — dont l'identité tailnet, **falsifiable**, qui interdit de s'en servir comme contrôle d'accès |
| `Le transport est DÉJÀ compressé` | gzip est monté par le harness devant **toutes** les réponses : le plugin n'a rien à activer, et rien à ajouter |
| `Deux noms de journal` | le second nom de fichier, et le quart des sessions qui n'existaient pas pour l'application |
| `Le service est absent de la composition` | une **capture précoce** : un service lu dans `apply()` peut ne pas exister encore |
| `Une erreur avalée a coûté une heure` | `ctx.get` rend `undefined`, pas `null` — et une exception convertie en `400` vide ne dit rien |
| `Le piège : dans un waterfall` | un observateur placé **après** le répondeur n'est jamais appelé |
| `Ce qui a été mesuré, et qui a coûté du temps` | le **chemin** du binaire Tailscale décide du succès, pas seulement sa présence |
| `Ce qui est gardé en mémoire` | 84 Mio d'objets contre 48 Mio de texte : ce qui est mis en cache, et pourquoi c'est du texte |
| `Ce qui a été prouvé, et comment` | chaque affirmation du README, avec la preuve qui la porte |

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

## Le transport est DÉJÀ compressé — mesuré, et c'est le harness qui le fait

**IL N'Y A RIEN À ACTIVER DANS LE PLUGIN, ET C'EST UNE MESURE, PAS UNE SUPPOSITION.**
Le serveur web du harness (`@deepseek-ai/dsh-host-webserver`) monte un intergiciel
gzip (`compression`, niveau 1, seuil 1 024 octets) devant **toutes** les réponses —
routes de plugin comprises, puisque l'intergiciel enveloppe le gestionnaire de
requêtes avant le routage. Le bundle `dsh-web-app` l'active déjà :

```yaml
# @deepseek-ai/dsh-web-app/cordis.patch.yml, ligne « webserver »
compression: gzip
compressionLevel: 1
compressionThresholdBytes: 1024
```

Le défaut du paquet, lui, est `none` : un déploiement SANS le bundle web ne
compresse rien. C'est le seul cas où il faut l'activer — et cela se fait dans le
profil, pas dans le plugin :

```yaml
- id: webserver
  config: { compression: gzip }
```

**Ce que ça donne, mesuré sur l'instance réelle** (profil `web`, plugin chargé,
`curl` en boucle locale avec le jeton de l'appareil, `Accept-Encoding: gzip`) :

| Route | Sans compression | Avec compression | Gain |
|---|---|---|---|
| `POST /v1/sessions` (200 sessions) | 138 429 octets | **19 317 octets** | **7,2×** (−86 %) |
| `POST /v1/session/<id>` (200 enregistrements) | 492 021 octets | **129 656 octets** | **3,8×** (−74 %) |

Le corps décompressé est **identique octet pour octet** à celui servi sans
compression (même SHA-256), et les en-têtes disent ce qu'ils font :
`Content-Encoding: gzip`, `Vary: Accept-Encoding`, `Transfer-Encoding: chunked`
(le `Content-Length` est retiré par l'intergiciel).

**POURQUOI LE PLUGIN N'AJOUTE PAS SA PROPRE COMPRESSION.** Ce serait du code mort
au mieux — l'intergiciel saute les réponses qui portent déjà un
`Content-Encoding` — et deux seuils configurables pour une seule décision au pire.
Le harness possède déjà ce mécanisme, à un endroit qui couvre aussi l'interface
web : le plugin le réutilise, comme il réutilise le serveur et sa clôture de
confiance (RÈGLE #0, interdit #7).

**L'`ETag` RESTE CELUI DU CONTENU, POUR LES DEUX CODAGES — et c'est assumé.** Un
validateur fort devrait distinguer les représentations (RFC 9110 § 8.8.1) ; ici
l'empreinte désigne le CONTENU, que le transport compresse ou non — c'est le
comportement de l'intergiciel, mesuré : les deux réponses portent le même `ETag`.
La confusion qu'un cache partagé pourrait en faire est hors de portée : les
réponses portent `cache-control: no-store`, il n'y a qu'un client par jeton, et
`Vary: Accept-Encoding` est posé. Le client, lui, ne s'en aperçoit pas : il
compare ce qu'il a reçu à ce qu'on lui renvoie.

**Ce que le client annonce, mesuré aussi** : `URLSession` (CFNetwork 3896, macOS
27) envoie `Accept-Encoding: gzip, deflate` — ni `br`, ni `zstd`. Une compression
brotli ou zstd n'aurait donc aucun preneur côté application, et `node:zlib` ne
propose zstd que sur les versions de Node qui l'exposent. gzip est le seul
codage qui sert ici.

---

## Carnets — comment une règle est née

Ces six récits suivent le même plan : le défaut observé, la mesure qui l'a établi, le
remède, et la règle que le dépôt en a tirée.

### Deux noms de journal — et 39 sessions qui n'existaient pas

DSH a écrit ses journaux sous `session.jsonl.zstd`, puis sous
`session.v3.jsonl.zstd`. Le plugin ne cherchait **que le second** : mesuré sur
cette machine, **118 sessions au nom v3 et 39 au nom historique**. Les 39 autres
n'existaient donc pas pour l'application — invisibles, sans erreur, sans
avertissement.

Elles se décodent pourtant parfaitement : la première essayée a rendu **6 356
enregistrements**, en-tête complet, `cwd` et titre présents. Le format de
concaténation de trames zstd est le même.

`trouverJournal` essaie donc les deux noms, le v3 d'abord — s'il est là, c'est lui
qui fait foi. Mesuré après correction : **148 sessions** au lieu de 118, aucune
sans identifiant, et une session au journal historique se lit (20 enregistrements
sur la première page).

C'est le TEST DE CONTRAT qui a mené là : en écrivant le fixture que les deux
côtés doivent s'accorder à produire et à décoder, la question « d'où vient ce nom
de fichier ? » s'est posée — et la vérification sur le disque a montré qu'il était
faux pour un quart des sessions.

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

### Ce qui est gardé en mémoire, et POURQUOI DU TEXTE — c'est une mesure

`lireSession` relit et redécompresse le journal **entier** à chaque page, et le
client en demande deux d'affilée (l'en-tête à l'ouverture, puis la première page).
Le cache évite donc la seconde décompression — et le résultat est mesuré, sur un
journal de **3 Mio compressés** (37 196 enregistrements) :

| Appel | Sans le cache | Avec |
|---|---|---|
| première page (froid) | 225 ms | **224 ms** — la décompression reste à payer |
| seconde page (chaud) | 225 ms | **36 ms** |
| lectures disque | une par page | **une seule** par version du journal |

**CE QUI EST GARDÉ : LES LIGNES DÉCOMPRESSÉES, PAS LES OBJETS ANALYSÉS.** C'est le
résultat d'une mesure, et elle est contre-intuitive. Sur le plus gros journal de
cette installation (9,7 Mio compressés, 37 989 enregistrements), le tas de Node
croît de **84 Mio** quand on matérialise les objets JS, soit **8,7 fois le
fichier** — dont 42 Mio pour la seule décompression. Garder les objets ferait donc
payer 84 Mio de mémoire du harness par journal chaud, pour épargner une analyse
JSON de quelques millisecondes. On garde le texte, et on réanalyse.

**LES DEUX BORNES, ET POURQUOI ELLES SONT DEUX.** 8 entrées au maximum (LRU : la
plus ancienne part), et **48 Mio de texte** au total. Le nombre seul ne suffirait
pas — huit journaux de 60 Mio tiendraient un demi-gigaoctet — et le total seul non
plus : un journal plus gros que le plafond n'entre **pas du tout**, plutôt que
d'évincer tout le reste pour un seul usage.

**LA RÈGLE VIT DANS SON PROPRE FICHIER** (`dynamic/cache-texte.js`), et c'est un
aveu utile : ce cache a d'abord été écrit en ligne dans `host.js`, à l'intérieur de
`apply` — donc **invérifiable seul**. Deux tentatives de test ont échoué
(`mock.method` ne peut pas redéfinir `readFile` d'un module natif : « Cannot
redefine property » ; `mock.module` exige un drapeau que le lanceur de tests
n'accepte pas). Un test impossible à écrire était le signal que la pièce était mal
découpée : extraite, elle reçoit ses deux dépendances et s'éprouve avec un
**compteur de lectures disque** — 8 tests dans `tests/cache-texte.test.js`, dont
l'invalidation par la date, l'éviction LRU et le journal trop gros pour le plafond.

---

## Ce qui a été prouvé, et comment

| Affirmation | Preuve |
|---|---|
| Une route nommée échappe à l'authentification navigateur | `200` sans cookie sur `/dsh-remote-probe/ping` (sonde), là où `/` répond `401` |
| Le tailnet atteint la route | `200` via le nom MagicDNS du Mac (`tailscale serve`) |
| L'hôte publie la liste du tailnet | instance neuve : `GET /v1/serveurs` → 3 Macs, `local: true` sur celui qui répond, et **NI** l'iPhone (iOS ne peut pas héberger DSH) |
| Un PC Windows EST proposé | `analyserTailnet` sur la sortie réelle de `tailscale status --json` : `MiBook` (`OS: windows`) apparaît, l'iPhone (`OS: iOS`) non — règle corrigée le 13 septembre 2026, voir « Découverte des serveurs » |
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
| **Un flux suit UNE session : le second `demarrer` est refusé** | `tests/hote.test.js` : un flux ouvert sur `session-aaa`, un second `demarrer` sur `session-bbb` → une seule `base`, un refus nommé (`un flux suit deja une session`), et la connexion **reste ouverte** |
| **Un client qui ne répond plus est FERMÉ** | même fichier, horloge simulée (`node:test` mock timers) : un ping sans pong ne ferme pas ; deux pings sans aucun pong ferment en `1008` — et un client qui répond à ses trois pings garde son flux |
| Sans jeton : refus | `401` sur `/v1/sante` et sur l'`Upgrade` WebSocket |
| **Un jeton en lecture seule n'écrit pas** | 10 tests (`tests/portee.test.js`) : l'écriture et l'annulation rendent `403 jeton en lecture seule` ET le contrôleur de session n'est **jamais** appelé ; un jeton d'écriture passe ; un enregistrement sans portée reste en écriture |
| **La capacité d'écriture suit la portée** | `capacites.ecriture` et `capacites.annulation` valent `false` en lecture seule, `true` en écriture — l'application cache son composeur sur ce booléen |
| Avec `Origin` : refus | `403` |
| L'identité tailnet est falsifiable | `curl` local avec `Tailscale-User-Login: attaquant@exemple.fr` → accepté |
| Le jeton est stocké en `0600` | permissions lues sur `~/.dsh/.credentials.yaml` |
| Traversée de chemin refusée | `POST /v1/session/..%2f..%2fetc%2fpasswd` → `404` |
| Identifiant inconnu refusé | `404` |
| Le journal se décode entièrement | 172 trames, 914 Ko, 62 ms, **0 ligne illisible** |
| Le client Swift lit réellement les données | `dsh-remote-ctl <tailnet> sessions 6` affiche 486 évts et une date sur la session courante |
| **Le bundle écrit à la main se charge SANS compilation** | `tests/bundle.test.js` exécute le fichier réel derrière un faux `window.__ModuleLoader__.load` : le `id` est celui du paquet, `apply` enregistre `sidebar.footer.action`, et l'absence de `slots` ou de React **dégrade sans lever** |
| **La copie de l'encodeur n'a pas dérivé** | comparaison **caractère pour caractère** du bloc d'encodeur avec la référence figée `tests/encodeur-reference.js` — le bloc d'origine, gelé le 14 septembre 2026 à la suppression de `share-qr` (`tests/bundle.test.js`) |
| **Le module hôte se charge, et enregistre toutes ses routes** | `tests/hote.test.js` importe `dynamic/host.js` hors harness : les six routes et l'`Upgrade` du flux sont là, chacune avec un gestionnaire. C'est la panne « import manquant » qui n'apparaissait qu'en instance neuve (`500 listage impossible`) |
| **La route d'appairage est gardée, et dans le bon ordre** | même fichier : `503` sans service navigateur, `401` sans cookie **avant toute lecture**, `405` en `POST`, et le chemin nominal rend une charge utile que l'analyseur du contrat relit — jamais une adresse de boucle locale |
| **Le QR est lisible par une implémentation INDÉPENDANTE** | la matrice du bundle est rendue en BMP (sans dépendance) et **décodée par Vision/macOS** : `payloadStringValue` rend la charge utile exacte |
| **Les deux moitiés analysent pareil** | 61 tests JS + la suite Swift rejouent le **même fixture** : charges valides, 15 refus (7 motifs), seuils de secret, et les bornes de laxité du nom d'hôte |
| **L'application applique l'appairage sans mélanger les hôtes** | `AppairageAppliqueTests.swift` : adresse ET jeton posés ensemble, jeton de l'hôte précédent conservé, refus qui ne change **rien** |
| **Le flux d'appairage complet, sans harness** | `tests/hote.test.js` : frappe → échange → jeton neuf de 43 caractères → il authentifie `/v1/sante` → portée `lecture` → la route d'écriture le refuse en `403 jeton en lecture seule` |
| **Un code ne sert qu'une fois, et il expire** | même fichier : second échange du même code → `403 code inconnu ou deja utilise` ; après la durée de vie → `403 code expire`, puis le code reste brûlé |
| **La révocation est PAR APPAREIL** | même fichier : deux appareils appairés, révocation du premier par empreinte → son jeton rend `401`, le second et l'historique continuent de rendre `200` |
| **Le jeton historique survit à la mise à jour** | même fichier : le registre est un SECOND enregistrement ; l'ancien jeton reste valide et devient la première entrée de la liste |
| **Un nom d'appareil hostile est nettoyé** | même fichier : `\n`, commande bidi et 200 caractères → nom sans retour à la ligne, sans inversion d'affichage, borné à 40 |
| **Trois `403` ne se confondent plus** | `AppairageEchangeTests.swift` : un `403` de code devient `appairageRefuse` (motif traduit), la portée reste `ecritureRefusee`, l'origine reste `origineRefusee` |
| **L'appareil échange, il ne range pas le code** | `AppairageAppliqueTests.swift` : le code part à l'échange avec l'adresse et un nom ; c'est le jeton REÇU qui va au trousseau, jamais le code |
| **Reste à éprouver APRÈS REDÉMARRAGE** : le panneau (bouton **« DSH Remote »** et son **sifflet**), le compte à rebours, le scan iPhone, le collage macOS et la révocation depuis l'écran | procédure en **12 points** dans « Appairer un appareil » — **non faite à ce jour** |

Un bug réel a été trouvé par cette méthode : le client Swift attendait du
`snake_case` quand le plugin émet du `camelCase`. Les tests Swift « passaient »
parce qu'ils avaient été écrits contre la même hypothèse fausse ; c'est la
comparaison avec la charge utile réelle qui l'a révélé. Les tests vérifient
désormais explicitement `nbEnregistrements` et `dernierEvenementLe`.
