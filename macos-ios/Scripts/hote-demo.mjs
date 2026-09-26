// UN HÔTE DE DÉMONSTRATION — le VRAI plugin, nourri de sessions FICTIVES.
//
// POURQUOI IL EXISTE. Les captures de la fiche App Store (et une vidéo pour la
// review) doivent montrer l'application en marche, avec des sessions crédibles —
// mais RIEN de réel : ni nom de machine, ni tailnet, ni chemin, ni jeton
// (RÈGLE #0). Ce script charge `plugin/dynamic/host.js` tel quel, sans harness,
// derrière un vrai serveur HTTP local, et lui donne :
//
//   - un `DSH_HOME` TEMPORAIRE, rempli de journaux inventés (même format que le
//     vrai : JSONL compressé zstd, une trame par enregistrement) ;
//   - un faux coffre dont le jeton se dit fictif (`JETONFICTIF-…`) ;
//   - de faux agents : une session « au travail », une autre « en attente de
//     réponse », les autres inactives ;
//   - une liste de machines FICTIVE : la route `/v1/serveurs` est interceptée,
//     parce que le plugin interrogerait le binaire Tailscale de CETTE machine et
//     publierait les vrais noms du tailnet dans les captures.
//
// Usage : node Scripts/hote-demo.mjs [port]      (défaut : 3080)
// Le jeton à coller dans l'app est imprimé au démarrage — il est fictif.

import { createServer } from 'node:http'
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import zlib from 'node:zlib'

const port = Number(process.argv[2] ?? '3080')
const JETON = 'JETONFICTIF-demo-captures-00000000000000000'

// ── Les sessions inventées ────────────────────────────────────────────────────

const racine = await mkdtemp(join(tmpdir(), 'dsh-remote-demo-'))
process.env.DSH_HOME = racine
// Le plugin cherche aussi `~/.local/bin/tailscale` : on l'éloigne du vrai HOME.
process.env.HOME = racine

const maintenant = Date.now()
const minute = 60_000

const texte = (t) => [{ type: 'text', text: t }]
const utilisateur = (t) => ({ type: 'user/message', data: { message: { role: 'user', content: texte(t) } } })
const assistant = (t) => ({ type: 'assistant/message', data: { message: { role: 'assistant', content: texte(t) } } })
const outil = (nom, args, id) => ({ type: 'tool/call', data: { name: nom, arguments: JSON.stringify(args), callId: id } })
const resultat = (t, id) => ({
  type: 'tool/result',
  data: { callId: id, message: { role: 'tool', source: { kind: 'tool', callId: id }, content: texte(t) } },
})
const titre = (t) => ({ type: 'session/title', data: { title: t } })

const SESSIONS = [
  {
    id: 'demo-offline-cache',
    cwd: '/work/weatherapp',
    ilYa: 1,
    enregistrements: [
      titre('Add an offline cache to the weather app'),
      utilisateur('Add an offline cache so the forecast still shows without network. Keep it under 5 MB.'),
      assistant('I will add a disk cache in front of the forecast client, with a size cap and an expiry.'),
      outil('read_file', { path: 'Sources/Forecast/ForecastClient.swift' }, 'c1'),
      resultat('ForecastClient.swift — 142 lines read', 'c1'),
      outil('edit_file', { path: 'Sources/Forecast/ForecastCache.swift' }, 'c2'),
      resultat('Created ForecastCache.swift (+86 lines)', 'c2'),
      outil('run_command', { command: 'swift test --filter ForecastCacheTests' }, 'c3'),
      resultat('Test run with 12 tests passed after 0.41 seconds.', 'c3'),
      assistant('The cache is in place and all 12 tests pass. Next: wire it into the refresh flow.'),
    ],
  },
  {
    id: 'demo-flaky-login',
    cwd: '/work/webstore',
    ilYa: 4,
    enregistrements: [
      titre('Fix the flaky login test'),
      utilisateur('The login UI test fails one run out of five. Find out why.'),
      outil('run_command', { command: 'npm test -- login.spec.ts --repeat 20' }, 'd1'),
      resultat('17 passed, 3 failed: timeout waiting for #session-banner', 'd1'),
      assistant('The banner appears after an animation that the test does not await. Should I add an explicit wait, or disable animations in the test environment?'),
    ],
  },
  {
    id: 'demo-release-notes',
    cwd: '/work/webstore',
    ilYa: 38,
    enregistrements: [
      titre('Draft release notes for 2.3'),
      utilisateur('Draft the release notes for version 2.3 from the merged pull requests.'),
      outil('run_command', { command: 'git log v2.2..HEAD --merges --oneline' }, 'e1'),
      resultat('14 merge commits', 'e1'),
      assistant('Release notes drafted in CHANGELOG.md: 3 features, 6 fixes, 5 internal changes.'),
    ],
  },
  {
    id: 'demo-billing-refactor',
    cwd: '/work/billing',
    ilYa: 180,
    enregistrements: [
      titre('Refactor the invoice module'),
      utilisateur('Split InvoiceService into smaller units without changing behaviour.'),
      assistant('Done: InvoiceService now delegates to TaxCalculator and InvoiceRenderer. All 58 tests pass.'),
    ],
  },
]

const trame = (objet) => zlib.zstdCompressSync(Buffer.from(JSON.stringify(objet) + '\n', 'utf8'))
const projetDe = (cwd) => '--' + cwd.replace(/^\//, '').replace(/\//g, '-') + '--'

for (const session of SESSIONS) {
  const debut = maintenant - session.ilYa * minute - session.enregistrements.length * 20_000
  const lignes = [{ type: 'session', id: session.id, cwd: session.cwd, createdAt: debut, agentPreset: 'standard' }]
  session.enregistrements.forEach((enregistrement, rang) => {
    lignes.push({ ...enregistrement, seq: rang + 1, time: debut + (rang + 1) * 20_000 })
  })
  const dossier = join(racine, 'sessions', projetDe(session.cwd), session.id)
  await mkdir(dossier, { recursive: true })
  await writeFile(join(dossier, 'session.v3.jsonl.zstd'), Buffer.concat(lignes.map(trame)))
}

// ── Le contexte factice du harness ────────────────────────────────────────────

const enregistrements = new Map([
  ['dsh-remote/device-token', { kind: 'grant', payload: { token: JETON, creeLe: 0, portee: 'lecture' } }],
])
const coffre = {
  readRecord: async (cle) => enregistrements.get(cle),
  modifyRecord: async (cle, fabrique) => {
    const suivant = await fabrique(enregistrements.get(cle))
    if (suivant !== undefined) enregistrements.set(cle, suivant)
    return enregistrements.get(cle)
  },
  deleteRecord: async (cle) => {
    enregistrements.delete(cle)
  },
}

const STATUTS = {
  'demo-offline-cache': 'running',
  'demo-flaky-login': 'idle',
  'demo-release-notes': 'idle',
  'demo-billing-refactor': 'idle',
}
const agents = {
  get: (id) => (id in STATUTS ? { id, status: STATUTS[id] } : undefined),
  roots: () => Object.keys(STATUTS).map((id) => ({ id })),
}

const routes = []
const upgrades = []
const ecouteurs = new Map()
const ctx = {
  get(service) {
    if (service === 'webServer') {
      return {
        register: (route) => (routes.push(route), () => {}),
        registerUpgrade: (route) => (upgrades.push(route), () => {}),
      }
    }
    if (service === 'credentials') return coffre
    if (service === 'agents') return agents
    if (service === 'connection') {
      return { browserAuth: { isAuthenticated: () => true }, trustedHosts: ['studio.example.test'] }
    }
    return undefined
  },
  on(nom, ecouteur) {
    ecouteurs.set(nom, [...(ecouteurs.get(nom) ?? []), ecouteur])
  },
  effect: () => {},
}

const ici = dirname(fileURLToPath(import.meta.url))
const { apply } = await import(join(ici, '..', '..', 'plugin', 'dynamic', 'host.js'))
apply(ctx, { journaliser: false })

// Une question en attente sur « flaky login » : le plugin compte les demandes
// qui traversent `user-questions/request` jusqu'à leur réponse. Celle-ci ne
// reçoit jamais de réponse — la session reste « attend votre réponse ».
for (const ecouteur of ecouteurs.get('user-questions/request') ?? []) {
  ecouteur({ agent: { id: 'demo-flaky-login' } }, () => new Promise(() => {}))
}

// ── Le serveur HTTP ───────────────────────────────────────────────────────────

const MACHINES_FICTIVES = {
  protocole: 1,
  // LA MACHINE PUBLIÉE EST CET HÔTE MÊME. Un nom inventé serait sondé par l'app,
  // ne répondrait pas, et la capture montrerait un diagnostic d'échec ; une
  // liste vide ferait dire « aucune machine sur le tailnet ».
  serveurs: [{ nom: 'Studio', nomDNS: `127.0.0.1:${port}`, enLigne: true, local: true }],
  diagnostic: null,
}

const trouver = (liste, chemin) =>
  liste.find((route) => route.path === chemin) ??
  liste.find((route) => route.kind === 'prefix' && chemin.startsWith(route.path + '/'))

const serveur = createServer((req, res) => {
  const chemin = (req.url ?? '/').split('?')[0]
  if (chemin === '/dsh-remote/v1/serveurs') {
    res.writeHead(200, { 'content-type': 'application/json' })
    return res.end(JSON.stringify(MACHINES_FICTIVES))
  }
  const route = trouver(routes, chemin)
  if (route === undefined) {
    res.writeHead(404)
    return res.end()
  }
  route.handler(req, res)
})
serveur.on('upgrade', (req, socket, tete) => {
  const route = trouver(upgrades, (req.url ?? '/').split('?')[0])
  if (route === undefined) return socket.destroy()
  if (tete?.length) socket.unshift(tete)
  route.handler(req, socket)
})

serveur.listen(port, '127.0.0.1', () => {
  console.log(`hôte de démo : http://127.0.0.1:${port}`)
  console.log(`jeton (fictif) : ${JETON}`)
})

const arreter = async () => {
  serveur.close()
  await rm(racine, { recursive: true, force: true })
  process.exit(0)
}
process.on('SIGINT', arreter)
process.on('SIGTERM', arreter)
