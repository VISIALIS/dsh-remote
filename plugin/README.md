# dsh-remote — surface JSON pour une application native

Ce plugin donne à une application **native** (Swift, macOS et iOS) une surface
JSON versionnée pour observer l'instance DSH qui tourne sur le Mac. Il ne
remplace pas l'interface web : il expose à un programme ce que l'interface web
ne sait dire qu'à un navigateur.

Il porte aussi, depuis l'**appairage par QR**, un panneau dans l'interface web :
le Mac y affiche un QR code — et son texte — qui remplit l'adresse *et* le jeton
d'un seul geste sur l'appareil à rattacher. Ce qui circule est un **code à usage
unique de deux minutes**, jamais le jeton d'appareil : chaque appareil reçoit le
sien en échangeant ce code, et se révoque tout seul depuis le panneau. Voir
« Appairer un appareil » et « Sécurité ».

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

## Appairer un appareil — le QR, et ce qu'il transporte

**Le problème que ça résout.** Le jeton d'appareil ne s'affichait qu'une fois, au
terminal, à sa création. Le rattachement d'un appareil demandait donc deux saisies
sur deux écrans : l'adresse, puis 43 caractères recopiés à la main — et une faute
de frappe coûtait une rotation de jeton, puisque plus rien ne le réaffichait. Le
deuxième appareil, lui, exigeait de relire le coffre avec `dsh-remote-ctl`.

**Ce que ça ne résout pas**, et il faut le dire : Tailscale sur l'appareil, le Mac
visible, le port publié. Les quatre étapes du parcours de mise en service restent.
C'est la **transcription du secret** qui disparaît.

### La charge utile — un contrat entre deux langages

```
dshremote://<hote>/<genre>/v1/<secret>
```

| Segment | Ce qu'il porte | Pourquoi ainsi |
|---|---|---|
| `<hote>` | le nom MagicDNS **sans point final** | c'est l'adresse joignable d'un autre appareil, et celle que le profil déclare comme hôte de confiance |
| `<genre>` | `jeton` (étape A) ou `code` (étape B) | un jeton se garde, un code s'échange et expire : les confondre donnerait un `401` incompréhensible |
| `v1` | la version du contrat, **par genre** | un client qui ne connaît pas la version refuse en le disant, au lieu de l'essayer |
| `<secret>` | base64url, donc sans `/` | le découpage du chemin n'est jamais ambigu |

Le **port est implicite** (80, la convention que `tailscale serve` publie) : un
champ de plus serait un champ de plus à faire diverger. Mesure sur un hôte réel de
40 caractères : **105 octets**, soit un QR de **version 6, ECC M, 41 × 41
modules** (capacité 106) — et l'encodeur couvre jusqu'à la version 10 (214 octets).

**LES DEUX MOITIÉS SONT ÉPROUVÉES CONTRE LE MÊME FICHIER.** Une charge utile est
construite en JavaScript (l'hôte) et analysée en Swift (l'application) : rien
n'aurait signalé une divergence avant l'appairage, chez l'utilisateur. Le fixture
`packages/dsh-remote-swift/Tests/DSHRemoteKitTests/Fixtures/vecteurs-appairage.json`
est rejoué par `tests/appairage.test.js` **et** par `AppairageTests.swift` : les
charges valides, les refus (sept motifs), les seuils de secret, et jusqu'aux
**bornes de laxité** du nom d'hôte — `mauvais-.exemple.test` est accepté des deux
côtés, parce que la règle est « commence et finit alphanumérique », pas une règle
DNS par étiquette. C'est la divergence qui coûte, pas la laxité.

**UN GENRE CONNU N'EST PAS UN GENRE TRAITÉ.** Le contrat connaît `code` — la
grammaire est commune aux deux moitiés, et le fixture le prouve — mais l'étape A
n'échange rien : l'application **refuse** une charge utile `code` avec un message
qui dit quoi faire (« mettez l'application à jour, ou scannez le QR code d'un
jeton »). Sans ce refus, elle rangerait 22 caractères dans le champ du jeton, les
enverrait comme jeton porteur, et l'utilisateur récolterait un `401` — c'est-à-dire
une chasse à la panne d'authentification là où il manque une version. C'est éprouvé
(`AppairageAppliqueTests.swift`) : après le refus, **rien** n'a bougé, ni l'adresse,
ni le jeton, ni le trousseau.

### Les trois routes de l'appairage — et la seule gardée par le NAVIGATEUR

Toutes les autres routes de ce plugin authentifient le **jeton d'appareil** et
refusent tout `Origin`. Celles-ci font l'inverse pour trois d'entre elles, et
c'est délibéré : c'est la page de l'utilisateur, sur sa propre machine, qui les
appelle — pour frapper un code, voir les appareils, en révoquer un.

| Route | Méthode | Garde | Rôle |
|---|---|---|---|
| `/dsh-remote/v1/appairage` | `POST` | **session navigateur** | frappe un **code à usage unique** (2 min) et rend la charge utile à afficher |
| `/dsh-remote/v1/appareils` | `GET` | **session navigateur** | les appareils appairés : nom, portée, date, **empreinte** — jamais un jeton |
| `/dsh-remote/v1/appareils/revoquer` | `POST` | **session navigateur** | coupe UN appareil, désigné par son empreinte |
| `/dsh-remote/v1/appairage/echange` | `POST` | **le code lui-même** | rend un jeton **propre à l'appareil** ; aucun `Origin` toléré |

**LE JETON D'APPAREIL N'EST PLUS PUBLIÉ PAR AUCUNE ROUTE.** À l'étape A, la
route rendait le jeton lui-même — une dérogation assumée, dont la conséquence
était écrite noir sur blanc : une photo de l'écran valait le jeton **pour
toujours**. Ce qui circule maintenant est un code qui expire en deux minutes, ne
sert qu'une fois, et ne vit qu'en mémoire chez l'hôte. Le seul moment où un jeton
sort d'une route, c'est l'échange — et il sort **neuf**, pour l'appareil qui a
présenté le code.

```json
// POST /dsh-remote/v1/appairage  →  200
{
  "protocole": 1,
  "genre": "code",
  "version": "v1",
  "adresse": "http://<nom-magicdns>",
  "charge": "dshremote://<nom-magicdns>/code/v1/<22 caracteres>",
  "porteeFuture": "lecture",
  "expireLe": 1789220160414,
  "via": "tailscale"
}
```

- **Le cookie est vérifié en premier** (`connection.browserAuth.isAuthenticated`) :
  une requête refusée ne lit ni le coffre ni Tailscale, et repart avec une réponse
  fixe (`401`).
- **Le secret n'est jamais tracé.** `tracer` écrit la méthode, le chemin sans
  paramètre, le code et un complément court (« code tailscale », « echange iPhone »).
  Jamais la charge utile, jamais un jeton.
- **Jamais une adresse de boucle locale.** `nomDeLHote` prend le `Self` de
  Tailscale, sinon l'hôte déclaré au profil ; si les deux manquent, la route
  répond `503` avec sa raison au lieu d'émettre un QR qui ne mène nulle part.
- **La frappe est plafonnée** (30 par minute, tous clients confondus) et **huit
  codes vivants au maximum** ; les codes périmés sont retirés **avant** le plafond,
  sinon huit codes expirés bloqueraient la frappe d'un neuvième. Le plafond est
  **global, pas par adresse** : mesuré et documenté plus haut, derrière
  `tailscale serve` l'adresse source vaut toujours `127.0.0.1` — un plafond
  « par IP » serait une illusion de contrôle.

#### `POST /v1/appairage/echange` — le seul chemin qui rend un jeton

```json
// en-tête : Authorization: Bearer <code>   corps : { "nom": "iPhone de Camille" }
{
  "protocole": 1,
  "jeton": "<43 caracteres, NEUF>",
  "portee": "lecture",
  "nom": "iPhone de Camille",
  "creeLe": 1789220160414
}
```

- **L'ORDRE DES OPÉRATIONS EST DÉLIBÉRÉ** : forme, provenance, **consommation du
  code**, puis écriture. Le code est consommé **avant** l'écriture au coffre : un
  échec du coffre brûle le code au lieu de le laisser rejouable — l'appareil
  redemande un code, ce qui est un désagrément ; un code rejouable serait une
  faille.
- **Deux refus, un seul code** : « code inconnu ou déjà utilisé » et « code
  expiré » sont deux `403` distincts. Le premier ne dit pas si le texte a existé —
  le dire renseignerait un porteur de code deviné — et les deux se réparent
  pareil : on redemande un code.
- **Le nom vient du client, donc du réseau** : il est **nettoyé** avant d'entrer
  dans la liste (`nomDAppareil`) — longueur bornée à 40, caractères de commande,
  commandes bidi et largeurs nulles retirés. Un `\n` fabriquerait une fausse ligne
  dans la liste, et un `U+202E` inverserait l'affichage du nom : une liste
  illisible est une liste où l'on révoque le mauvais appareil.
- **Un hôte trop ancien** (sans cette route) rend `404` : l'application le
  traduit en « cet hôte ne sait pas échanger un code d'appairage », ce qui est un
  remède différent de « ce code a expiré ».
- **Le `429`** (plafond d'échanges) est un « réessayez », pas un refus d'appairage.

### Le registre des jetons, et la portée par appareil

| Enregistrement du coffre | Ce qu'il porte | Qui l'écrit |
|---|---|---|
| `dsh-remote/device-token` | le jeton **historique** (celui du terminal) | le plugin, à la création — **jamais réécrit** depuis |
| `dsh-remote/device-tokens` | `{ jetons: [ { token, portee, creeLe, nom } ] }` — un par appareil appairé | le plugin, à chaque échange et à chaque révocation |

**POURQUOI UN SECOND ENREGISTREMENT, ET PAS UNE RÉÉCRITURE DU PREMIER.** Le jeton
historique reste lu **tel quel** : une mise à jour du plugin ne doit pas retirer un
droit acquis, et un retour en arrière du plugin doit continuer de fonctionner. Les
deux sources sont valides en même temps, et l'historique est simplement la
**première entrée** de la liste.

**LA PORTÉE EST DEVENUE PAR APPAREIL.** Elle était une variable de module — il n'y
avait qu'un jeton, donc une seule portée. Chaque entrée porte maintenant la sienne,
et la requête lit celle de **l'appareil qui a parlé** : marquée **sur la réponse**
(un `Symbol`), jamais dans une variable de module. Une variable écrasée à chaque
requête serait juste « en pratique » — Node est mono-thread et le gestionnaire lit
la portée dans le même tour — mais elle deviendrait fausse le jour où une route
attend entre l'authentification et la lecture. La réponse, elle, appartient à sa
requête par construction.

**La comparaison reste à temps constant**, longueurs égalisées, et la boucle les
fait **toutes** (aucune sortie anticipée) : la durée ne dit donc pas à quelle
position le jeton a été trouvé. Le nombre d'appareils, lui, est public — il est
affiché.

**La révocation est par appareil, et elle passe par la session navigateur.** Le
geste vit dans le panneau, pas dans une route native : un porteur de jeton ne doit
pas pouvoir expulser les autres. Ce que cela coûte est dit au README, section
« Sécurité ».

### Le panneau — un `client.js` écrit à la main, sans compilation

Le panneau vit dans le pied de la barre latérale (`sidebar.footer.action`) : c'est
un geste **global**, qui ne dépend d'aucune session ouverte.

Ce dépôt connaissait deux formes de plugin ; celle-ci est la **troisième**, et elle
a été mesurée avant d'être écrite, dans le harness installé (v0.1.5-rc.1) :

| Étape | Ce que fait DSH | Référence |
|---|---|---|
| 1 | il remonte du module hôte au `package.json` **le plus proche**, lit `dsh.client` | `dsh-client-modules/lib/index.js` (`resolveMeta`, `locatePkgJson`) |
| 2 | il résout `exports["./client"]` et **lit le fichier tel quel** | `index.js` (`initialBundleSnapshot`) |
| 3 | il le sert sous `/plugins/<nom-du-paquet>/client.js`, l'identifiant du graphe étant le **nom du paquet** | `index.js` (`graphRow(packageName, …)`) |
| 4 | le navigateur consomme un tableau CJS paresseux : `window.__ModuleLoader__.load({ id, factory })` | `dsh-client-modules/lib/client.js:1-6` |

**Aucune compilation n'est exigée par DSH.** C'est ce qui rend le panneau
**durable** — contrairement à `share-qr`, posé par `cordis_define`, qui disparaît
au redémarrage : un panneau qu'il faut reposer à la main pour rattacher un
appareil serait un piège.

Deux conséquences pratiques, apprises en écrivant ce fichier :

- **`id` doit être le nom du paquet.** Le chargeur refuse un bundle qui enregistre
  un autre identifiant — et la panne est SILENCIEUSE côté utilisateur : le panneau
  est simplement absent ;
- **le `package.json` doit déclarer `"type": "module"`.** Sans lui, Node ne casse
  pas le chargement mais émet `MODULE_TYPELESS_PACKAGE_JSON` et **re-parse** le
  module hôte à chaque démarrage (mesuré sur Node v26.8.2).

Le panneau **ne reconstruit pas** la charge utile : la route la lui donne déjà
construite par `dynamic/appairage.js`. Deux constructions du même contrat
finiraient par diverger — c'est précisément ce que le fixture partagé évite
ailleurs. Il ne garde rien non plus : la charge utile quitte l'état React et le DOM
dès la fermeture.

**Deux points du shell ont été vérifiés dans le code installé**, parce que deux
hypothèses silencieuses auraient pu rendre le panneau inatteignable ou muet :

| Question | Réponse mesurée | Conséquence |
|---|---|---|
| Le pied de la barre latérale est-il rendu quand elle est REPLIÉE ? | `renderSlot("sidebar.footer.action", { wide })` est rendu **sans condition** dans `footArea` ; `wide` n'est qu'une prop | le bouton reste atteignable en 56 px de rail — d'où le libellé affiché seulement si `wide` |
| Une CSP interdirait-elle le `fetch` same-origin du panneau ? | **aucune** `Content-Security-Policy` n'est servie pour la page du shell (la seule du harness garde les références média : `sandbox; default-src 'none'`) | la route est joignable depuis la page ; si un jour une CSP apparaissait, le panneau afficherait « L'hôte n'a pas répondu », pas un écran vide |

### L'épreuve, après un redémarrage du harness

Le code du panneau n'est **pas** rechargé à chaud (voir « Ce que `patchReload: live`
recharge ») : il exige un **processus neuf**. C'est la seule épreuve que ce dépôt ne
peut pas faire à ta place, et voici exactement ce qu'il faut regarder.

```bash
# 1. les vérifications qui, elles, ne demandent AUCUN redémarrage
bash scripts/verifier.sh --tout
node --test plugins/dsh-remote/tests/

# 2. puis relancer le harness, et regarder la sortie du terminal : trois lignes
#    doivent apparaître, dont celle-ci, avec le nombre d'appareils connus
#    [dsh-remote] appairage (appareil): POST /dsh-remote/v1/appairage/echange — N appareil(s) connu(s)
```

| # | À observer | Ce que ça prouve |
|---|---|---|
| P1 | le panneau « Appairer » est dans le pied de la barre latérale ; l'icône ouvre une carte avec un **QR code** et un **compte à rebours** | un `client.js` écrit à la main est servi et exécuté **sans compilation** |
| P2 | `curl -i -X POST http://127.0.0.1:3080/dsh-remote/v1/appairage` → `401` ; avec un cookie de navigateur → `200` **et aucun jeton dans le corps** | la route est gatée par la session du navigateur, et le jeton n'est plus publié |
| P3 | l'adresse affichée est le **nom MagicDNS**, jamais `127.0.0.1` ; `expireLe` est à ~2 minutes | l'hôte publie une adresse joignable, et le code est daté |
| P4 | le QR se scanne depuis l'iPhone (Ajouter un serveur → Adresse → **Scanner le QR code**) et la connexion part seule | un geste remplace deux saisies |
| P5 | sur macOS, **Coller un appairage** (le texte sous le QR) remplit l'adresse et le jeton | le Mac ne peut pas scanner son propre écran — la forme texte est la représentation canonique, pas un repli |
| P6 | **le compte à rebours arrive à zéro**, le QR disparaît, et « Générer un nouveau code » en redonne un | un code EXPIRÉ ne peut plus être échangé — c'est ce qui rend une photo d'écran sans valeur |
| P7 | l'appareil appairé apparaît dans **« Appareils appairés »** avec son nom, sa portée et sa date ; l'adresse dans l'app est celle du Mac | le registre est écrit, et le nom vient bien de l'appareil |
| P8 | **Révoquer** cet appareil (deux appuis : « Révoquer », puis « Confirmer ») : il disparaît de la liste, et l'application de cet appareil reçoit `401` à la requête suivante | la révocation est **par appareil** — la limite que l'étape A ne levait pas |
| P9 | `curl -s http://127.0.0.1:3080/dsh-remote/v1/sante -H "Authorization: Bearer <jeton d'un appareil>"` → `portee`, `capacites.ecriture` et `appareils` | la portée est **par appareil**, et le compte est publié sans la liste |
| P10 | rejouer le même code (`curl -X POST …/appairage/echange -H "Authorization: Bearer <code>"`) une seconde fois → `403 code inconnu ou deja utilise` | un code ne sert **qu'une fois** |

Ce qui est **déjà** prouvé sans redémarrage, par les tests : l'encodeur embarqué
est identique caractère pour caractère à celui de `share-qr` ; sa matrice est
**décodée par Vision/macOS** (implémentation indépendante) et rend la charge utile
exacte ; le bundle s'annonce avec le bon `id`, enregistre le bon slot et se dégrade
sans lever quand `slots` ou React manquent ; le module hôte se charge et enregistre
ses routes ; le flux complet frappe → échange → jeton → portée → révocation est
rejoué de bout en bout ; le contrat est rejoué des deux côtés.

---

## Les fichiers, et les tests

Le plugin est un **module ES**, chargé par le loader d'un profil : il peut donc
être découpé en plusieurs fichiers, contrairement à un plugin posé par
`cordis_define`.

| Fichier | Ce qu'il porte |
|---|---|
| `dynamic/host.js` | le plugin : les routes, le cache, le flux, les jetons, le registre des appareils, les codes d'appairage |
| `dynamic/appairage.js` | le contrat d'appairage — fonctions **pures** (construction, analyse, nom d'appareil), éprouvées et partagées avec le Swift |
| `dynamic/client.js` | le panneau : **bundle client durable écrit à la main** (encodeur QR, compte à rebours, liste des appareils, révocation), servi tel quel par DSH |
| `package.json` | ce qui rend `client.js` **découvrable** (`dsh.client`, `exports["./client"]`) — aucune installation promise (RÈGLE #5) |
| `dynamic/tailscale.js` | la découverte du tailnet — lancement du CLI local et **analyse pure** de sa sortie |
| `dynamic/journal.js` | la lecture d'un journal de session : trames zstd concaténées, lignes JSONL, résumé |
| `dynamic/trames.js` | le protocole WebSocket écrit à la main (RFC 6455) : texte, ping, pong, fermeture |
| `tests/appairage.test.js` | le contrat d'appairage, rejoué contre le fixture **partagé avec le Swift** |
| `tests/hote.test.js` | le module hôte chargé **hors harness** : routes et gardes, puis le flux complet frappe → échange → jeton → portée → révocation |
| `tests/bundle.test.js` | le bundle RÉEL : `id`, slot, dégradation, copie de l'encodeur, et décodage par Vision |
| `tests/outils/qr-vers-bmp.js` | l'image du QR, écrite sans dépendance (BMP non compressé), pour l'épreuve de décodage |
| `tests/outils/decoder-qr.swift` | le décodeur **indépendant** (Vision/macOS) qui lit cette image |
| `tests/tailscale.test.js` | les règles de la découverte, éprouvées sans lancer Tailscale |
| `tests/journal.test.js` | les règles de lecture du journal, éprouvées avec de vraies trames zstd |
| `tests/contrat.test.js` | le contrat avec le client : le plugin produit exactement les clés du fixture |
| `tests/trames.test.js` | le protocole WebSocket, éprouvé octet par octet |

```bash
node --test plugins/dsh-remote/tests/     # 69 tests, aucune dépendance

POURQUOI LE MODULE HÔTE EST CHARGÉ HORS HARNESS. C'est la panne qui a déjà coûté une
instance neuve : un import manquant (`cheminIndicatif`) ne casse pas `node --check`,
il casse au CHARGEMENT, chez l'utilisateur, sous la forme d'un `500` sans trace. Le
test importe donc `dynamic/host.js`, vérifie que les dix routes sont là avec un
gestionnaire, puis rejoue le parcours d'appairage entier sur un coffre en mémoire —
y compris les chemins qu'on ne veut jamais voir en vrai : code expiré, code rejoué,
empreinte inconnue, révocation du jeton historique sans `deleteRecord`.

POURQUOI LE BUNDLE A SES PROPRES TESTS, ET CE QU'ILS ATTRAPENT. Le panneau est un
`client.js` écrit à la main, sans compilation : trois pannes y sont SILENCIEUSES —
un `id` qui ne correspond pas au nom du paquet (le chargeur refuse d'enregistrer,
le panneau est simplement absent), une copie d'encodeur qui a dérivé, un
enregistrement de slot mal formé. Le test charge donc le bundle **réel** derrière
un faux `window.__ModuleLoader__.load`, compare son encodeur, caractère pour
caractère, à celui de `share-qr`, et fait décoder sa matrice par Vision — une
implémentation qui ne partage aucune ligne avec lui. Le test de décodage est
**sauté** si `swift` est absent, et il le dit : un contrôle qui ne s'exécute pas ne
doit pas passer pour un contrôle.

POURQUOI LES TRAMES ONT DES TESTS. C'est du code **binaire** écrit à la main pour
ne pas ajouter de dépendance (RÈGLE #0) : une longueur mal encodée, un masque mal
appliqué, et le flux se tait sans rien dire — le client attend, le serveur croit
avoir envoyé. Les tests couvrent les trois formes de longueur (deux octets, deux
octets étendus, huit octets), le masque des trames CLIENTES (la RFC l'impose, et
le serveur ne masque jamais), une trame incomplète conservée pour le morceau
suivant, une longueur démesurée REFUSÉE avant d'allouer, et l'acceptation du
handshake comparée à la valeur de l'exemple de la RFC. Vérifié en plus en vrai :
un client WebSocket minimal reçoit `101 Switching Protocols` puis une trame
`base`.
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

### Portée du jeton — `lecture` ou `ecriture`

**Le problème que la portée résout.** Le jeton était tout-puissant : il ouvrait la
lecture **et** l'écriture (`/v1/session/<id>/prompt`, `/v1/session/<id>/annuler`).
Un jeton qui fuit donnait donc à son porteur le pouvoir d'**écrire dans l'agent de
quelqu'un d'autre** — la première question qu'on pose à un client publié. La portée
y répond par construction : un jeton `lecture` lit tout et n'écrit rien.

| Situation | Portée | Ce que ça donne |
|---|---|---|
| Jeton **neuf** (installation neuve) | `lecture` | Lit ; l'écriture répond `403 jeton en lecture seule` |
| Jeton neuf avec `DSH_REMOTE_PORTEE=ecriture` | `ecriture` | Lit et écrit |
| Enregistrement **d'avant la portée** (aucun champ `portee`) | `ecriture` | Inchangé : une mise à jour du plugin ne retire pas un droit acquis |

**Pourquoi la lecture seule par défaut.** Une installation neuve n'a aucune raison
d'accorder l'écriture, et le dépôt public doit pouvoir répondre « un jeton fuité
n'écrit rien » sans condition. Qui veut écrire le demande, explicitement :

```bash
DSH_REMOTE_PORTEE=ecriture dsh web          # tire un jeton qui écrit
```

La portée se décide **à la création du jeton**, et pas après : pour changer de
portée, il faut supprimer l'enregistrement `dsh-remote/device-token` du coffre et
relancer le harness, qui en tire un neuf. Le terminal dit alors, à la création, ce
que le jeton autorise — c'est le seul endroit où l'utilisateur l'apprend.

**Ce qui est protégé, et ce qui ne l'est pas.** La portée borne ce que le **jeton**
autorise ; elle ne remplace pas le jeton (sans jeton valide, rien ne passe : `401`),
elle ne chiffre rien (le transport est celui de Tailscale), et elle ne restreint pas
la lecture — un jeton `lecture` voit **tout** ce que voit un jeton `ecriture`,
journaux compris.

**Deux refus, un seul code.** Le `403` sert à deux causes, et le corps les
distingue par `erreur` :

```json
{ "erreur": "origine refusee" }
{ "erreur": "jeton en lecture seule", "portee": "lecture", "detail": "…" }
```

Un client qui ne lirait pas ce champ afficherait « un client natif ne doit jamais
envoyer d'en-tête Origin » à quelqu'un dont le jeton lit simplement sans écrire —
un message faux, donc un remède faux. Le côté application lit ce champ
(`ErreurRemote.ecritureRefusee`), et les deux moitiés ont un test sur la chaîne
exacte (`tests/portee.test.js`, `Tests/DSHRemoteKitTests/PorteeLectureTests.swift`).

**La portée est annoncée** dans `GET /v1/sante` (champ `portee`), et
`capacites.ecriture` / `capacites.annulation` valent `false` quand elle est
`lecture` : l'application cache alors son composeur **et dit pourquoi**. Sans cette
annonce, elle proposerait un bouton qui recevrait un `403`.

`portee` est **absent** des réponses d'un hôte antérieur à la portée : un client
doit lire `nil` comme « ne sait pas », jamais comme « lecture seule ».

---

## Protocole

Toutes les routes sont sous `/dsh-remote/v1/`. Le champ `protocole` est présent
dans **chaque** réponse : un client qui ne sait pas lire une version doit le
dire, pas deviner.

Authentification : `Authorization: Bearer <jeton>`. Jamais de jeton en paramètre
d'URL — un paramètre finit dans un journal d'accès ou un historique.

**QUATRE ROUTES ÉCHAPPENT À CETTE RÈGLE**, et elles forment la surface
d'appairage : trois sont gatées par la **session du navigateur**
(`browserAuth.isAuthenticated`) parce que c'est la page de l'utilisateur qui les
appelle, et la quatrième (`/v1/appairage/echange`) par le **code** lui-même, qu'un
appareil présente avant d'avoir un jeton. Voir « Appairer un appareil » et
« Sécurité ».

| Route | Méthode | Rôle |
|---|---|---|
| `/dsh-remote/v1/sante` | `GET` | Poignée de main : version du protocole, capacités, **portée du jeton**. Aucune donnée. |
| `/dsh-remote/v1/sessions` | `GET`, `POST` | Liste des sessions, de la plus récente à la plus ancienne. |
| `/dsh-remote/v1/espaces` | `GET` | Espaces de travail du registre de l'hôte, **ceux sans session compris**, dans son ordre de création décroissante. |
| `/dsh-remote/v1/serveurs` | `GET` | Liste des machines du tailnet qui peuvent héberger DSH, **découverte par l'hôte** — c'est ce qui donne une liste à l'iPhone. |
| `/dsh-remote/v1/appairage` | `POST` | **Session navigateur.** Frappe un code à usage unique et rend la charge utile à afficher. Jamais tracée, `no-store`. |
| `/dsh-remote/v1/appareils` | `GET` | **Session navigateur.** Les appareils appairés : nom, portée, date, empreinte — jamais un jeton. |
| `/dsh-remote/v1/appareils/revoquer` | `POST` | **Session navigateur.** Coupe un appareil, désigné par son empreinte. |
| `/dsh-remote/v1/appairage/echange` | `POST` | **Le code fait office de porteur.** Rend un jeton neuf, propre à l'appareil. Aucun `Origin` toléré. |
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

**Un jeton en `lecture` est refusé ici, et nulle part ailleurs dans cette route** :

```json
403 { "erreur": "jeton en lecture seule", "portee": "lecture", "detail": "…" }
```

Le refus tombe **avant toute action** : ni le contrôleur de session ni le journal ne sont
touchés. Voir « Portée du jeton » plus haut.

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
  binaire introuvable, Tailscale muet, délai dépassé, aucune machine dans le tailnet.
  Quatre causes qui ne se corrigent pas de la même façon. Une liste vide sans raison est
  indébogable.
- **Seules les machines qui PEUVENT héberger DSH sont retenues** — macOS, Windows,
  Linux. La règle disait `macOS` seulement, et elle était **fausse** : « proposer un PC
  Windows ou un iPhone comme serveur DSH serait une promesse que l'installation ne peut
  pas tenir ». Le propriétaire a relevé la confusion — « il y a un serveur windows qui
  n'est pas listé, or le serveur DSH est universel non ? c'est juste le remote qui est
  macOS ou iOS ». DSH est un harness **Node** : il tourne aussi sur Windows (le harness
  publie un bac à sable Windows ACL) et sur Linux. C'est l'**application** qui est macOS
  et iOS, pas l'hôte.
- Ce qui reste écarté, ce sont les systèmes qui **ne peuvent pas exécuter de
  processus** : iOS, iPadOS, Android, tvOS. Un iPhone ne peut pas héberger DSH. La liste
  est donc une **liste blanche** — un système inconnu n'est pas proposé — et elle est
  identique à celle du client (`DecouverteServeurs.systemesQuiHebergent`) : deux listes
  qui divergeraient feraient apparaître une machine d'un côté et pas de l'autre.
- **Elle ne promet pas qu'une machine serve DSH** : elle dit qu'elle *pourrait*
  l'héberger. C'est la sonde du client qui tranche, et une machine qui ne répond pas
  s'affiche « pas de DSH ».

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
déroge sur **trois** points, délibérés et documentés ici.

### Il affiche un identifiant porteur (interdit #3)

À sa création, le jeton est écrit **en clair dans le terminal**. C'est le seul
canal d'amorçage disponible : l'application iPhone n'a aucun autre moyen
d'apprendre le secret, et une route qui le rendrait serait pire.

**Risque** : une capture d'écran de ce terminal, ou un enregistrement de session,
donne le contrôle de la surface de lecture. **Garde-fous** : le jeton est affiché
une seule fois ; il n'est jamais journalisé par `tracer` (qui ne trace que
méthode, route, code et compteur) ; le coffre est en `0600`.

### L'échange REND un jeton — à qui présente un code

Ce README posait, avant l'appairage : « le jeton n'est **jamais** renvoyé par une
route HTTP, pas même à un client authentifié : une route qui rendrait le jeton
serait un oracle ». L'étape A avait transgressé cette règle en publiant le jeton
d'appareil dans un QR — dérogation assumée, mais dont la conséquence était lourde :
une photo de l'écran valait le jeton **pour toujours**, et cette photo pouvait venir
d'un autre panneau (`share-qr` publie l'URL navigateur authentifiée).

**L'étape B a refermé cela, et la règle d'origine est rétablie** : aucune route ne
rend le jeton d'appareil. Ce que `POST /v1/appairage/echange` rend est un jeton
**neuf, propre à l'appareil**, et seulement à qui présente un **code à usage unique
de deux minutes**. La dérogation se réduit donc à ce qu'elle doit être :

**Ce qui la sépare d'un oracle** : ni la session navigateur ni un jeton existant ne
suffisent — il faut un code vivant, frappé sur geste, consommé au premier échange.
Le nombre de codes vivants est plafonné à huit, leur frappe à trente par minute.

**LA CHAÎNE QU'IL FAUT CONNAÎTRE, ET ELLE A CHANGÉ DE PORTÉE.** `share-qr` affiche
l'URL navigateur **authentifiée** ; une photo de ce panneau donne un cookie valide,
et ce cookie ouvre `POST /v1/appairage`, qui **frappe un code**. Une photo donne donc
un code — valable **deux minutes**, à usage unique, et seulement si personne ne l'a
déjà échangé. C'est écrit ici **et** dans le README de `share-qr` : une chaîne de ce
genre doit se trouver en lisant l'un **ou** l'autre, jamais en les recoupant.

**Risque résiduel, dit sans le minimiser** : qui photographie l'écran pendant ces
deux minutes, **et échange le premier**, obtient un jeton d'appareil — en portée
`lecture` par défaut. C'est borné dans le temps, ça ne répond à aucune approbation,
et ça se révoque appareil par appareil. À l'étape A, la même photo valait un jeton
permanent : la fenêtre est passée de « toujours » à « deux minutes ».

### Révoquer un appareil passe par la SESSION NAVIGATEUR

`GET /v1/appareils` et `POST /v1/appareils/revoquer` sont gardés par la session du
navigateur, **pas** par un jeton d'appareil. C'est délibéré : un porteur de jeton ne
doit pas pouvoir expulser les autres — sinon le premier jeton qui fuit permettrait
de déconnecter tous les appareils de l'utilisateur.

**Ce que cela coûte** : qui obtient la session navigateur (donc, aujourd'hui, qui
obtient le cookie — voir la chaîne ci-dessus) peut **révoquer** des appareils. C'est
un déni de service sur ses propres appareils, jamais une fuite : la révocation ne
révèle rien et ne donne aucun accès. Le remède est immédiat — réappairer.

**Il n'y a pas de route NATIVE de gestion des appareils**, et c'est un choix : elle
exposerait la liste à tout porteur de jeton, et elle ferait de `dsh-remote-ctl` un
**second lecteur du coffre** — un lecteur qui se trompe afficherait un jeton. Le
terminal sait seulement **combien** d'appareils sont appairés (champ `appareils` de
`/v1/sante`) ; pour les voir et en révoquer un, c'est le panneau.

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
- **Aucun `Origin` toléré sur les routes NATIVES** : refusé en `403` **avant** le
  test du jeton. Un client natif n'en envoie jamais, un navigateur en envoie
  toujours — c'est la barrière anti-CSRF et anti-DNS-rebinding. **L'exception est
  `/v1/appairage`**, qui EST une route de navigateur : elle n'accepte pas d'`Origin`
  par tolérance, elle l'attend, et c'est la session du navigateur qui la garde.
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
| `credentials.readRecord` / `.modifyRecord` | stocker le jeton historique ET le registre des appareils | sans coffre, aucune authentification n'est possible : toutes les routes répondent `401` |
| `credentials.deleteRecord` | révoquer le jeton **historique** (il vit dans son propre enregistrement) | la révocation de l'historique répond `503 coffre incapable de supprimer` — jamais un « ok » qui n'aurait rien supprimé |
| `sessions.get`, `agents.roots` | marquer une session `vivante` | `vivante` vaut `false` partout ; le reste fonctionne |
| `sessionController.prompt` / `.cancel` | écrire et interrompre | `capacites.ecriture` vaut `false`, la lecture continue de fonctionner, les deux routes répondent `503` |
| `workspaceRegistry.list()` | publier les espaces de travail, **vides compris** | `capacites.espaces` vaut `false` et `/v1/espaces` répond `503` ; le client retombe sur le regroupement des sessions par `cwd` |
| `ctx.on('user-questions/request' \| 'approval/request', …, { prepend: true })` | signaler qu'une décision humaine est attendue | `attendReponse` reste `false` partout : l'indicateur disparaît, rien d'autre ne casse |
| `connection.browserAuth.isAuthenticated(req)` | garder la route d'appairage | le panneau affiche « authentification navigateur indisponible » et n'émet rien (réponse `503`) |
| `connection.trustedHosts` | repli d'adresse quand Tailscale est muet | l'hôte retombe sur `Self` de Tailscale, puis sur un refus explicite |
| client : `slots.inject` / `slots.register('sidebar.footer.action')` | poser le panneau | RÈGLE #3 : le bundle journalise l'absence et **ne lève pas** — la page de l'utilisateur continue de fonctionner |
| client : `require('react')` (table de modules du shell) | dessiner la carte | même dégradation, testée (`tests/bundle.test.js`) |
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
| **La copie de l'encodeur n'a pas dérivé** | comparaison **caractère pour caractère** du bloc d'encodeur avec celui de `share-qr` (`tests/bundle.test.js`) |
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
| **Reste à éprouver APRÈS REDÉMARRAGE** : le panneau, le compte à rebours, le scan iPhone, le collage macOS et la révocation depuis l'écran | procédure en **10 points** dans « Appairer un appareil » — **non faite à ce jour** |

Un bug réel a été trouvé par cette méthode : le client Swift attendait du
`snake_case` quand le plugin émet du `camelCase`. Les tests Swift « passaient »
parce qu'ils avaient été écrits contre la même hypothèse fausse ; c'est la
comparaison avec la charge utile réelle qui l'a révélé. Les tests vérifient
désormais explicitement `nbEnregistrements` et `dernierEvenementLe`.

---

## Limites connues

- **La fenêtre d'appairage est de deux minutes, et elle est réelle.** Qui
  photographie l'écran pendant ce temps **et échange le premier** obtient un jeton
  d'appareil — en portée `lecture` par défaut. C'est la limite de tout appairage
  par QR ; elle est bornée dans le temps, à usage unique, et révocable appareil par
  appareil. La durée est réglable (`config.ttlCodeMs`, bornée entre 1 s et 15 min).
- **Un code frappé mais non échangé reste en mémoire jusqu'à son expiration**, et
  huit au maximum. Un panneau qu'on ouvre et qu'on ferme dix fois consomme le
  plafond de frappe (30/minute) : c'est un « réessayez », pas une panne.
- **La révocation passe par la session navigateur**, donc par le cookie. Qui
  obtient ce cookie (voir la chaîne `share-qr`) peut révoquer des appareils — un
  déni de service sur ses propres appareils, jamais une fuite.
- **Révoquer le jeton historique ne le remplace pas tout de suite** : le plugin en
  tire un neuf au prochain démarrage du harness, et c'est le seul moyen — il n'y a
  pas de « tourner le jeton » à chaud.
- **Le panneau ne peut pas être ouvert depuis un appareil sans session
  navigateur.** Sa route exige le cookie de l'interface web : ce n'est pas un
  défaut, c'est ce qui la garde — mais cela veut dire qu'on appaire depuis la page
  du Mac, pas depuis le téléphone.
- **La description d'usage de la caméra est en français seulement.** L'application
  est localisée (fr source, en ajouté), mais `NSCameraUsageDescription` vit dans
  l'`Info.plist`, dont la traduction demanderait un `InfoPlist.strings` qui n'existe
  pas encore. Un utilisateur anglophone verra donc une phrase française dans
  l'invite système — c'est écrit ici plutôt que découvert.
- **Aucun lien universel, aucun schéma déclaré** : le scan se fait **dans**
  l'application. Ouvrir l'appairage depuis la caméra système demanderait un
  `CFBundleURLTypes` et un `apple-app-site-association` servi par DSH — un sujet à
  part entière, pas un réglage.
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
| 6 | Appairage par QR — **étape A** : contrat versionné, panneau durable, scanner iPhone, collage macOS | **livrée**, puis **remplacée par l'étape B** : la route qui publiait le jeton d'appareil a été retirée, et la règle « le jeton n'est jamais renvoyé par une route » est rétablie |
| 6 | Appairage par QR — **étape B** : code à usage unique (2 min), échange contre un jeton **par appareil**, portée par appareil, liste et révocation dans le panneau | **écrite et éprouvée localement** (69 tests JS dont le flux complet, 230 tests Swift, construction iOS simulateur verte) ; l'épreuve du panneau exige un **redémarrage** du harness — procédure en **10 points** ci-dessus, **non encore exécutée** |
