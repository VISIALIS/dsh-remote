// Moitié CLIENT du plugin dsh-remote — LE PANNEAU D'APPAIRAGE.
//
// CE FICHIER N'EST NI UN MODULE ES, NI UN « CORPS DE FONCTION » (RÈGLE #2).
// C'est la TROISIÈME forme que ce dépôt rencontre : un BUNDLE CLIENT DURABLE,
// écrit à la main, que DSH lit TEL QUEL et sert au navigateur sous
// `/plugins/dsh-remote/client.js`. Aucune compilation n'est exigée par DSH :
//
//   - DSH remonte du module hôte (`dynamic/host.js`) au `package.json` le plus
//     proche, lit `dsh.client` (`platform: web`) et résout `exports["./client"]`
//     (mesuré : `dsh-client-modules/lib/index.js`, `resolveMeta` / `locatePkgJson`) ;
//   - il lit le fichier tel quel et le sert (`initialBundleSnapshot`) ;
//   - le navigateur consomme un tableau CJS paresseux : c'est la forme
//     ci-dessous, et `id` DOIT être le nom du paquet déclaré au `package.json`,
//     sans quoi le chargement échoue (« bundle loaded without registering »).
//
// POURQUOI CETTE FORME, ET PAS UN PLUGIN DYNAMIQUE. `share-qr` est posé par
// `cordis_define` : il disparaît au redémarrage du harness. Le panneau
// d'appairage, lui, doit survivre — c'est par lui qu'on rattache un appareil, et
// un panneau qu'il faut reposer à la main serait un piège.
//
// CE QUE CE FICHIER NE FAIT PAS : il n'importe rien du dépôt (le bundle est
// servi seul au navigateur), il ne lit aucun secret, et il ne décide de rien. Il
// DEMANDE un code à la route de son propre hôte, l'affiche, et le retire de son
// état dès la fermeture du panneau. Depuis l'étape B, ce qu'il affiche est un
// CODE À USAGE UNIQUE — jamais le jeton d'appareil, qui n'est plus publié par
// aucune route.
//
// Les trois routes qui le servent (`/v1/appairage`, `/v1/appareils`,
// `/v1/appareils/revoquer`) sont gatées par la SESSION NAVIGATEUR de
// l'utilisateur — jamais par un jeton d'appareil : un porteur de jeton ne doit
// pas pouvoir expulser les autres. Voir `host.js` et le README du plugin.

window.__ModuleLoader__.load({
  id: 'dsh-remote',
  factory: (require) => {
    var module = { exports: {} }
    var exports = module.exports

    // React vient de la table de modules du shell. Un échec ici ne doit pas
    // casser la page entière : le panneau s'annonce indisponible, un point.
    let React = null
    try {
      React = require('react')
    } catch (erreur) {
      React = null
    }

    // ── L'ENCODEUR QR ────────────────────────────────────────────────────────
    //
    // REPRIS TEL QUEL de `plugins/share-qr/dynamic/client.js`, où il est éprouvé
    // (vecteurs normatifs, et décodage par Vision/macOS). Il est COPIÉ et non
const SPEC = {
  1: [26, 10, 1], 2: [44, 16, 1], 3: [70, 26, 1], 4: [100, 18, 2], 5: [134, 24, 2],
  6: [172, 16, 4], 7: [196, 18, 4], 8: [242, 22, 4], 9: [292, 22, 5], 10: [346, 26, 5],
}
const ALIGN = {
  1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
  6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
}
const EC_BITS = 0
const EXP = new Array(512)
const LOG = new Array(256)
let seed = 1
for (let i = 0; i < 255; i++) {
  EXP[i] = seed
  LOG[seed] = i
  seed <<= 1
  if (seed & 0x100) seed ^= 0x11d
}
for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]
function gmul(a, b) {
  if (a === 0 || b === 0) return 0
  return EXP[LOG[a] + LOG[b]]
}
function rsGenPoly(n) {
  let poly = [1]
  for (let i = 0; i < n; i++) {
    const next = poly.concat([0])
    for (let j = 0; j < poly.length; j++) next[j + 1] ^= gmul(poly[j], EXP[i])
    poly = next
  }
  return poly
}
function rsRemainder(data, gen) {
  const res = data.concat(new Array(gen.length - 1).fill(0))
  for (let i = 0; i < data.length; i++) {
    const coef = res[i]
    if (coef !== 0) {
      for (let j = 0; j < gen.length; j++) res[i + j] ^= gmul(gen[j], coef)
    }
  }
  return res.slice(data.length)
}
function utf8Bytes(text) {
  const out = []
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i)
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00)
        i++
      }
    }
    if (code < 0x80) out.push(code)
    else if (code < 0x800) out.push(0xc0 | (code >> 6), 0x80 | (code & 63))
    else if (code < 0x10000) out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63))
    else out.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63))
  }
  return out
}
function byteCapacity(version) {
  const spec = SPEC[version]
  const dataWords = spec[0] - spec[1] * spec[2]
  return Math.floor((dataWords * 8 - (4 + (version <= 9 ? 8 : 16))) / 8)
}
function pickVersion(length) {
  for (let v = 1; v <= 10; v++) if (byteCapacity(v) >= length) return v
  throw new Error('lien trop long pour un QR de version 1 a 10')
}
function dataWords(bytes, version) {
  const spec = SPEC[version]
  const capacity = spec[0] - spec[1] * spec[2]
  const bits = []
  const push = (value, length) => {
    for (let i = length - 1; i >= 0; i--) bits.push((value >>> i) & 1)
  }
  push(4, 4)
  push(bytes.length, version <= 9 ? 8 : 16)
  for (let i = 0; i < bytes.length; i++) push(bytes[i], 8)
  const capacityBits = capacity * 8
  const terminator = Math.min(4, capacityBits - bits.length)
  for (let i = 0; i < terminator; i++) bits.push(0)
  while (bits.length % 8 !== 0) bits.push(0)
  const pads = [0xec, 0x11]
  let p = 0
  while (bits.length < capacityBits) {
    push(pads[p % 2], 8)
    p++
  }
  const words = []
  for (let i = 0; i < bits.length; i += 8) {
    let value = 0
    for (let j = 0; j < 8; j++) value = (value << 1) | bits[i + j]
    words.push(value)
  }
  return words
}
function interleave(words, version) {
  const spec = SPEC[version]
  const ecPerBlock = spec[1]
  const blocks = spec[2]
  const shortLen = Math.floor(words.length / blocks)
  const longCount = words.length % blocks
  const dataBlocks = []
  const ecBlocks = []
  const gen = rsGenPoly(ecPerBlock)
  let offset = 0
  for (let i = 0; i < blocks; i++) {
    const len = shortLen + (i >= blocks - longCount ? 1 : 0)
    const block = words.slice(offset, offset + len)
    offset += len
    dataBlocks.push(block)
    ecBlocks.push(rsRemainder(block, gen))
  }
  const out = []
  for (let i = 0; i <= shortLen; i++) {
    for (let b = 0; b < blocks; b++) if (i < dataBlocks[b].length) out.push(dataBlocks[b][i])
  }
  for (let i = 0; i < ecPerBlock; i++) {
    for (let b = 0; b < blocks; b++) out.push(ecBlocks[b][i])
  }
  return out
}
function formatBits(mask) {
  const data = (EC_BITS << 3) | mask
  let rem = data
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537)
  return ((data << 10) | rem) ^ 0x5412
}
function versionBits(version) {
  let rem = version
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25)
  return (version << 12) | rem
}
const MASKS = [
  (r, c) => (r + c) % 2 === 0,
  (r) => r % 2 === 0,
  (r, c) => c % 3 === 0,
  (r, c) => (r + c) % 3 === 0,
  (r, c) => (Math.floor(r / 2) + Math.floor(c / 3)) % 2 === 0,
  (r, c) => ((r * c) % 2) + ((r * c) % 3) === 0,
  (r, c) => (((r * c) % 2) + ((r * c) % 3)) % 2 === 0,
  (r, c) => (((r + c) % 2) + ((r * c) % 3)) % 2 === 0,
]
function buildMatrix(version, words, mask) {
  const size = version * 4 + 17
  const m = []
  const fixed = []
  for (let r = 0; r < size; r++) {
    m.push(new Array(size).fill(0))
    fixed.push(new Array(size).fill(false))
  }
  const set = (r, c, v) => {
    if (r < 0 || c < 0 || r >= size || c >= size) return
    m[r][c] = v
    fixed[r][c] = true
  }
  const finder = (r0, c0) => {
    for (let dr = -1; dr <= 7; dr++) {
      for (let dc = -1; dc <= 7; dc++) {
        const r = r0 + dr
        const c = c0 + dc
        if (r < 0 || c < 0 || r >= size || c >= size) continue
        const ringRow = dr >= 0 && dr <= 6 && (dc === 0 || dc === 6)
        const ringCol = dc >= 0 && dc <= 6 && (dr === 0 || dr === 6)
        const core = dr >= 2 && dr <= 4 && dc >= 2 && dc <= 4
        set(r, c, ringRow || ringCol || core ? 1 : 0)
      }
    }
  }
  finder(0, 0)
  finder(0, size - 7)
  finder(size - 7, 0)
  for (let i = 8; i < size - 8; i++) {
    const bit = i % 2 === 0 ? 1 : 0
    set(6, i, bit)
    set(i, 6, bit)
  }
  const centers = ALIGN[version]
  for (let a = 0; a < centers.length; a++) {
    for (let b = 0; b < centers.length; b++) {
      const cr = centers[a]
      const cc = centers[b]
      if ((cr <= 8 && cc <= 8) || (cr <= 8 && cc >= size - 9) || (cr >= size - 9 && cc <= 8)) continue
      for (let dr = -2; dr <= 2; dr++) {
        for (let dc = -2; dc <= 2; dc++) {
          const ring = Math.max(Math.abs(dr), Math.abs(dc))
          set(cr + dr, cc + dc, ring === 1 ? 0 : 1)
        }
      }
    }
  }
  const fmt = formatBits(mask)
  const bitOf = (value, i) => (value >>> i) & 1
  for (let i = 0; i <= 5; i++) set(i, 8, bitOf(fmt, i))
  set(7, 8, bitOf(fmt, 6))
  set(8, 8, bitOf(fmt, 7))
  set(8, 7, bitOf(fmt, 8))
  for (let i = 9; i < 15; i++) set(8, 14 - i, bitOf(fmt, i))
  for (let i = 0; i < 8; i++) set(8, size - 1 - i, bitOf(fmt, i))
  for (let i = 8; i < 15; i++) set(size - 15 + i, 8, bitOf(fmt, i))
  set(size - 8, 8, 1)
  if (version >= 7) {
    const ver = versionBits(version)
    for (let i = 0; i < 18; i++) {
      const bit = bitOf(ver, i)
      const a = size - 11 + (i % 3)
      const b = Math.floor(i / 3)
      set(b, a, bit)
      set(a, b, bit)
    }
  }
  let index = 0
  const totalBits = words.length * 8
  const nextBit = () => {
    if (index >= totalBits) return 0
    const value = (words[index >> 3] >>> (7 - (index & 7))) & 1
    index++
    return value
  }
  let upward = true
  for (let col = size - 1; col > 0; col -= 2) {
    if (col === 6) col = 5
    for (let i = 0; i < size; i++) {
      const r = upward ? size - 1 - i : i
      for (let k = 0; k < 2; k++) {
        const c = col - k
        if (fixed[r][c]) continue
        m[r][c] = nextBit()
      }
    }
    upward = !upward
  }
  const maskFn = MASKS[mask]
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) {
      if (!fixed[r][c] && maskFn(r, c)) m[r][c] ^= 1
    }
  }
  return m
}
function penalty(m) {
  const size = m.length
  let score = 0
  const scanRuns = (get) => {
    let run = 1
    for (let i = 1; i < size; i++) {
      if (get(i) === get(i - 1)) run++
      else {
        if (run >= 5) score += 3 + (run - 5)
        run = 1
      }
    }
    if (run >= 5) score += 3 + (run - 5)
  }
  for (let r = 0; r < size; r++) scanRuns((i) => m[r][i])
  for (let c = 0; c < size; c++) scanRuns((i) => m[i][c])
  for (let r = 0; r < size - 1; r++) {
    for (let c = 0; c < size - 1; c++) {
      const v = m[r][c]
      if (v === m[r][c + 1] && v === m[r + 1][c] && v === m[r + 1][c + 1]) score += 3
    }
  }
  const pat1 = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
  const pat2 = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
  const hit = (get, start, pat) => {
    for (let k = 0; k < 11; k++) if (get(start + k) !== pat[k]) return false
    return true
  }
  for (let r = 0; r < size; r++) {
    for (let c = 0; c + 11 <= size; c++) {
      const get = (i) => m[r][i]
      if (hit(get, c, pat1)) score += 40
      if (hit(get, c, pat2)) score += 40
    }
  }
  for (let c = 0; c < size; c++) {
    for (let r = 0; r + 11 <= size; r++) {
      const get = (i) => m[i][c]
      if (hit(get, r, pat1)) score += 40
      if (hit(get, r, pat2)) score += 40
    }
  }
  let dark = 0
  for (let r = 0; r < size; r++) {
    for (let c = 0; c < size; c++) if (m[r][c]) dark++
  }
  score += Math.floor(Math.abs((dark * 100) / (size * size) - 50) / 5) * 10
  return score
}
function encodeQr(text) {
  const bytes = utf8Bytes(text)
  const version = pickVersion(bytes.length)
  const words = interleave(dataWords(bytes, version), version)
  let best = null
  let bestMask = 0
  let bestScore = Infinity
  for (let mask = 0; mask < 8; mask++) {
    const candidate = buildMatrix(version, words, mask)
    const score = penalty(candidate)
    if (score < bestScore) {
      bestScore = score
      best = candidate
      bestMask = mask
    }
  }
  return { version: version, mask: bestMask, matrix: best }
}

    // ── LA CHARGE UTILE, ET SON CONTRAT ──────────────────────────────────────
    //
    // Le panneau ne CONSTRUIT rien : la route lui donne la charge utile déjà
    // construite par `dynamic/appairage.js` (la moitié hôte). Deux constructions
    // du même contrat finiraient par diverger — c'est précisément ce que le
    // fixture partagé évite ailleurs.
    //
    // ET IL NE PUBLIE PLUS LE JETON. Depuis l'étape B, ce que le panneau frappe
    // est un CODE : il expire, il ne sert qu'une fois, et il ne vit qu'en mémoire
    // chez l'hôte. C'est ce qui rend une photo de l'écran sans valeur — l'étape A
    // publiait le jeton lui-même, qui n'expirait jamais.
    const CHEMIN_APPAIRAGE = '/dsh-remote/v1/appairage'
    const CHEMIN_APPAREILS = '/dsh-remote/v1/appareils'
    const CHEMIN_REVOQUER = '/dsh-remote/v1/appareils/revoquer'

    const COULEURS = {
      texte: 'var(--dsw-alias-label-primary)',
      discret: 'var(--dsw-alias-label-secondary)',
      bord: 'var(--dsw-alias-border-l1)',
      fond: 'var(--dsw-alias-bg-overlay)',
      couche: 'var(--dsw-alias-bg-layer-1)',
      surcouche: 'var(--dsw-alias-bg-layer-2)',
      marque: 'var(--dsw-alias-brand-primary)',
      alerte: 'var(--dsw-alias-state-warn-primary)',
      danger: 'var(--dsw-alias-state-error-primary, #c0392b)',
      succes: 'var(--dsw-alias-state-success-primary)',
    }

    /**
     * Copie dans le presse-papiers, avec le repli des contextes non sécurisés.
     *
     * POURQUOI LE REPLI EXISTE. `navigator.clipboard` est refusé hors HTTPS (et
     * l'instance est jointe en HTTP sur le port 80 du tailnet). Sans repli, le
     * bouton « copier » ne ferait rien sur le chemin le plus courant — et un
     * bouton sans effet est un mensonge.
     */
    const copier = async (texte) => {
      try {
        if (typeof navigator !== 'undefined' && navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
          await navigator.clipboard.writeText(texte)
          return true
        }
      } catch (erreur) {
        // contexte non securise ou permission refusee : on tente le repli
      }
      try {
        if (typeof document === 'undefined' || typeof document.execCommand !== 'function' || !document.body) return false
        const zone = document.createElement('textarea')
        zone.value = texte
        zone.setAttribute('readonly', '')
        zone.style.position = 'fixed'
        zone.style.top = '-1000px'
        zone.style.left = '-1000px'
        zone.style.opacity = '0'
        document.body.appendChild(zone)
        zone.focus()
        zone.select()
        let ok = false
        try {
          ok = document.execCommand('copy') === true
        } finally {
          document.body.removeChild(zone)
        }
        return ok
      } catch (erreur) {
        return false
      }
    }

    const appel = async (chemin, options) => {
      // `corps` EST UNE COMMODITÉ, PAS UNE OPTION DE `fetch` : on la retire de
      // l'initialiseur plutôt que de la laisser s'y répandre. Un objet qui porte
      // une clé que personne ne lit est exactement ce qui fait perdre une heure
      // quand on le relit six mois plus tard.
      const init = { credentials: 'same-origin', headers: { accept: 'application/json' }, ...(options ?? {}) }
      delete init.corps
      if (options && options.corps !== undefined) {
        init.method = init.method !== undefined ? init.method : 'POST'
        init.headers = { ...init.headers, 'content-type': 'application/json' }
        init.body = JSON.stringify(options.corps)
      }
      const reponse = await fetch(chemin, init)
      let corps = null
      try {
        corps = await reponse.json()
      } catch (erreur) {
        corps = null
      }
      return { statut: reponse.status, corps }
    }

    /**
     * Le QR, dessiné en SVG.
     *
     * LA ZONE DE SILENCE EST DANS LE DESSIN (quatre modules autour), et ce n'est
     * pas un détail esthétique : un QR collé à son bord se scanne mal ou pas du
     * tout selon l'écran et l'angle. La porter ici évite de dépendre du rembourrage
     * d'une feuille de style.
     */
    const Plaque = ({ matrice }) => {
      const cote = matrice.length
      const marge = 4
      const morceaux = []
      for (let y = 0; y < cote; y++) {
        for (let x = 0; x < cote; x++) {
          if (matrice[y][x] === 1) morceaux.push('M' + String(x) + ' ' + String(y) + 'h1v1h-1z')
        }
      }
      const cadre = cote + 2 * marge
      return React.createElement(
        'div',
        { style: { padding: '10px', borderRadius: '10px', background: '#ffffff', lineHeight: 0 } },
        React.createElement(
          'svg',
          {
            width: 240,
            height: 240,
            viewBox: String(-marge) + ' ' + String(-marge) + ' ' + String(cadre) + ' ' + String(cadre),
            shapeRendering: 'crispEdges',
            role: 'img',
            'aria-label': "code d'appairage",
          },
          React.createElement('rect', { x: -marge, y: -marge, width: cadre, height: cadre, fill: '#ffffff' }),
          React.createElement('path', { d: morceaux.join(''), fill: '#000000' }),
        ),
      )
    }

    /** Le temps restant, en clair : « 1 min 47 s », « 12 s », « expiré ». */
    const dureeLisible = (secondes) => {
      if (!(secondes > 0)) return 'expiré'
      if (secondes < 60) return String(secondes) + ' s'
      const minutes = Math.floor(secondes / 60)
      const reste = secondes % 60
      return String(minutes) + ' min ' + String(reste) + ' s'
    }

    const dateLisible = (valeur) => {
      if (!Number.isFinite(valeur)) return 'date inconnue'
      try {
        return new Date(valeur).toLocaleString()
      } catch (erreur) {
        return 'date inconnue'
      }
    }

    /** Ce qu'on dit à l'utilisateur selon le code HTTP — jamais un code nu. */
    const expliquer = (statut, corps) => {
      if (statut === 401) return "Cette page n'a plus de session valide : rechargez l'interface DSH, puis rouvrez ce panneau."
      if (statut === 429) return 'Trop de codes demandés en une minute. Patientez un instant.'
      if (statut === 503) {
        const detail = corps !== null && typeof corps.detail === 'string' ? corps.detail : ''
        const erreur = corps !== null && typeof corps.erreur === 'string' ? corps.erreur : ''
        if (erreur === 'adresse injoignable') {
          return "L'hôte n'a pas d'adresse joignable par un autre appareil (" + detail + "). Tailscale est-il connecté sur ce Mac ?"
        }
        return detail.length > 0 ? "L'appairage est indisponible : " + detail : "L'appairage est indisponible sur cet hôte."
      }
      return "L'appairage n'a pas pu aboutir (code " + String(statut) + ")."
    }

    const boutonStyle = (principal) => ({
      padding: '6px 11px',
      borderRadius: '7px',
      border: '1px solid ' + (principal ? COULEURS.marque : COULEURS.bord),
      background: principal ? 'transparent' : COULEURS.couche,
      color: principal ? COULEURS.marque : COULEURS.texte,
      cursor: 'pointer',
      fontSize: '12px',
    })

    const ligne = (libelle, valeur, surCopie, copie) =>
      React.createElement(
        'div',
        { style: { display: 'flex', flexDirection: 'column', gap: '3px', width: '100%' } },
        React.createElement('span', { style: { fontSize: '11px', color: COULEURS.discret } }, libelle),
        React.createElement(
          'button',
          {
            type: 'button',
            onClick: () => surCopie(valeur),
            title: 'Cliquer pour copier',
            style: {
              boxSizing: 'border-box',
              width: '100%',
              padding: '7px 9px',
              borderRadius: '8px',
              border: '1px solid ' + (copie === valeur ? COULEURS.succes : COULEURS.bord),
              background: COULEURS.couche,
              color: copie === valeur ? COULEURS.succes : COULEURS.texte,
              fontFamily: 'ui-monospace,SFMono-Regular,Menlo,monospace',
              fontSize: '11px',
              lineHeight: 1.4,
              textAlign: 'left',
              wordBreak: 'break-all',
              cursor: 'pointer',
            },
          },
          copie === valeur ? 'Copié' : valeur,
        ),
      )

    /**
     * LE PANNEAU. Il vit dans le pied de la barre latérale : c'est un geste
     * GLOBAL, qui ne dépend d'aucune session ouverte — on appaire un appareil
     * avant d'avoir une conversation.
     */
    function BoutonAppairage(props) {
      const [ouvert, setOuvert] = React.useState(false)
      const [etat, setEtat] = React.useState('ferme')
      const [donnees, setDonnees] = React.useState(null)
      const [appareils, setAppareils] = React.useState([])
      const [message, setMessage] = React.useState('')
      const [copie, setCopie] = React.useState('')
      const [confirmation, setConfirmation] = React.useState('')
      const [restant, setRestant] = React.useState(0)
      const [rechargement, setRechargement] = React.useState(false)

      // LE CODE NE SURVIT PAS À LA FERMETURE : ni dans l'état, ni dans le DOM.
      // Un panneau qu'on oublie ouvert est déjà un risque — c'est pourquoi le code
      // expire de toute façon — mais un panneau fermé qui garde la charge utile en
      // mémoire n'a aucune raison d'être.
      const fermer = () => {
        setOuvert(false)
        setDonnees(null)
        setAppareils([])
        setEtat('ferme')
        setMessage('')
        setCopie('')
        setConfirmation('')
      }

      // UN SEUL CHARGEMENT À LA FOIS. Le rafraîchissement périodique (voir plus
      // bas) et les gestes de l'utilisateur peuvent se croiser : sans ce verrou,
      // deux réponses arriveraient dans le désordre et la plus ancienne écraserait
      // la plus récente — une liste qui « revient en arrière » toute seule.
      const listeEnCours = React.useRef(false)

      const chargerAppareils = async () => {
        if (listeEnCours.current) return false
        listeEnCours.current = true
        try {
          const { statut, corps } = await appel(CHEMIN_APPAREILS)
          if (statut === 200 && corps !== null && Array.isArray(corps.appareils)) {
            setAppareils(corps.appareils)
            return true
          }
          setMessage(expliquer(statut, corps))
          return false
        } finally {
          listeEnCours.current = false
        }
      }

      const frapper = async () => {
        setEtat('chargement')
        setMessage('')
        setDonnees(null)
        try {
          const { statut, corps } = await appel(CHEMIN_APPAIRAGE, { method: 'POST', corps: {} })
          if (statut !== 200 || corps === null || typeof corps.charge !== 'string') {
            setMessage(expliquer(statut, corps))
            setEtat('erreur')
            return
          }
          setDonnees(corps)
          setEtat('pret')
        } catch (erreur) {
          setMessage("L'hôte n'a pas répondu : l'interface est-elle toujours connectée ?")
          setEtat('erreur')
        }
      }

      const ouvrir = () => {
        setOuvert(true)
        setConfirmation('')
        frapper()
        chargerAppareils().catch(() => {})
      }

      const revoquer = async (empreinte) => {
        setRechargement(true)
        try {
          const { statut, corps } = await appel(CHEMIN_REVOQUER, { method: 'POST', corps: { empreinte } })
          if (statut !== 200) {
            setMessage(expliquer(statut, corps))
          } else {
            setMessage('')
          }
          await chargerAppareils()
        } catch (erreur) {
          setMessage("L'hôte n'a pas répondu : rien n'a été révoqué.")
        } finally {
          setConfirmation('')
          setRechargement(false)
        }
      }

      const surCopie = (valeur) => {
        copier(valeur).then((ok) => setCopie(ok ? valeur : ''))
      }

      // LE COMPTE À REBOURS EST UNE MESURE, PAS UNE DÉCORATION : il dit à
      // l'utilisateur combien de temps son écran vaut quelque chose.
      React.useEffect(() => {
        if (donnees === null || !Number.isFinite(donnees.expireLe)) return undefined
        const tic = () => setRestant(Math.max(0, Math.round((donnees.expireLe - Date.now()) / 1000)))
        tic()
        const minuterie = setInterval(tic, 1000)
        return () => clearInterval(minuterie)
      }, [donnees])

      // LA LISTE SE RAFRAÎCHIT TOUTE SEULE, et c'est ce qui manquait : elle n'était
      // lue qu'à l'ouverture et après une révocation. Conséquence constatée : un
      // appareil appairé PENDANT que le panneau est ouvert n'y apparaissait pas —
      // l'iPhone s'est appairé, le Mac s'est appairé juste après, et la liste est
      // restée à deux lignes alors que le registre en avait trois.
      React.useEffect(() => {
        if (!ouvert) return undefined
        const minuterie = setInterval(() => {
          chargerAppareils().catch(() => {})
        }, 5000)
        return () => clearInterval(minuterie)
      }, [ouvert])

      const bouton = React.createElement(
        'button',
        {
          type: 'button',
          onClick: ouvrir,
          title: 'Appairer un appareil (QR code)',
          style: {
            display: 'inline-flex',
            alignItems: 'center',
            gap: '7px',
            padding: '6px 9px',
            borderRadius: '7px',
            // UN BOUTON DOIT SE LIRE COMME UN BOUTON. Il était en
            // `label-secondary` — gris, fondu dans le pied de la barre — et il a
            // fallu le montrer sur capture pour que son propriétaire le trouve,
            // dans une interface où « Settings », juste en dessous, est en couleur
            // pleine. Même couleur que lui, donc, et une bordure discrète pour que
            // la zone cliquable se voie.
            border: '1px solid ' + COULEURS.bord,
            background: 'transparent',
            color: COULEURS.texte,
            cursor: 'pointer',
            fontSize: '12px',
          },
        },
        React.createElement(
          'svg',
          { width: 15, height: 15, viewBox: '0 0 16 16', fill: 'currentColor', 'aria-hidden': 'true' },
          React.createElement('path', {
            d: 'M1 1h5v5H1V1zm1.5 1.5v2h2v-2h-2zM10 1h5v5h-5V1zm1.5 1.5v2h2v-2h-2zM1 10h5v5H1v-5zm1.5 1.5v2h2v-2h-2zM10 10h2v2h-2v-2zm3 0h2v2h-2v-2zm-3 3h2v2h-2v-2zm3 0h2v2h-2v-2z',
          }),
        ),
        props !== undefined && props.wide === true ? React.createElement('span', null, 'Appairer') : null,
      )

      if (!ouvert) return bouton

      const contenu = []
      contenu.push(
        React.createElement(
          'div',
          { key: 'titre', style: { fontSize: '13px', fontWeight: 600, textAlign: 'center', color: COULEURS.texte } },
          'Appairer un appareil',
        ),
      )

      if (etat === 'chargement') {
        contenu.push(
          React.createElement('div', { key: 'attente', style: { fontSize: '12px', color: COULEURS.discret } }, 'Préparation du code…'),
        )
      }

      if (etat === 'erreur') {
        contenu.push(
          React.createElement(
            'div',
            {
              key: 'erreur',
              style: {
                boxSizing: 'border-box',
                width: '100%',
                padding: '10px',
                borderRadius: '8px',
                border: '1px solid ' + COULEURS.alerte,
                color: COULEURS.texte,
                fontSize: '12px',
                lineHeight: 1.45,
              },
            },
            message,
          ),
        )
      }

      if (etat === 'pret' && donnees !== null) {
        const expire = restant <= 0
        let matrice = null
        if (!expire) {
          try {
            matrice = encodeQr(donnees.charge).matrix
          } catch (erreur) {
            matrice = null
          }
        }
        if (expire) {
          contenu.push(
            React.createElement(
              'div',
              {
                key: 'expire',
                style: {
                  boxSizing: 'border-box',
                  width: '100%',
                  padding: '12px 10px',
                  borderRadius: '8px',
                  border: '1px solid ' + COULEURS.alerte,
                  color: COULEURS.texte,
                  fontSize: '12px',
                  lineHeight: 1.45,
                  textAlign: 'center',
                },
              },
              'Ce code a expiré. Il ne servait qu’une fois, et il n’ouvre plus rien.',
            ),
          )
        } else if (matrice === null) {
          contenu.push(
            React.createElement(
              'div',
              { key: 'qr-impossible', style: { fontSize: '12px', color: COULEURS.texte } },
              "Le code est trop long pour être dessiné. Copiez le texte ci-dessous dans l'application.",
            ),
          )
        } else {
          contenu.push(React.createElement(Plaque, { key: 'qr', matrice }))
        }
        contenu.push(
          React.createElement(
            'div',
            { key: 'consigne', style: { fontSize: '12px', lineHeight: 1.45, textAlign: 'center', color: COULEURS.discret } },
            expire
              ? 'Générez un nouveau code pour appairer un appareil.'
              : "Scannez ce code avec l'application DSH Remote (Ajouter un serveur → Scanner le QR code).",
          ),
        )
        if (!expire) {
          contenu.push(
            React.createElement(
              'div',
              { key: 'champs', style: { display: 'flex', flexDirection: 'column', gap: '8px', width: '100%' } },
              ligne('Adresse', donnees.adresse, surCopie, copie),
              ligne("Texte à coller dans l'application macOS", donnees.charge, surCopie, copie),
            ),
          )
          contenu.push(
            React.createElement(
              'div',
              {
                key: 'portee',
                style: {
                  boxSizing: 'border-box',
                  width: '100%',
                  padding: '9px 10px',
                  borderRadius: '8px',
                  background: COULEURS.couche,
                  color: COULEURS.texte,
                  fontSize: '11px',
                  lineHeight: 1.45,
                },
              },
              donnees.porteeFuture === 'lecture'
                ? "L'appareil recevra un jeton qui LIT sans écrire : il affichera les sessions sans proposer de composeur."
                : "L'appareil recevra un jeton qui autorise AUSSI À ÉCRIRE dans vos sessions.",
            ),
          )
          contenu.push(
            React.createElement(
              'div',
              {
                key: 'risque',
                style: {
                  boxSizing: 'border-box',
                  width: '100%',
                  padding: '9px 10px',
                  borderRadius: '8px',
                  border: '1px solid ' + COULEURS.alerte,
                  color: COULEURS.texte,
                  fontSize: '11px',
                  lineHeight: 1.45,
                },
              },
              'Ce code expire dans ' + dureeLisible(restant) + ' et ne sert qu’une fois. Fermez ce panneau après usage.',
            ),
          )
        }
      }

      // ── Les appareils appairés ─────────────────────────────────────────────
      contenu.push(
        React.createElement(
          'div',
          { key: 'appareils-titre', style: { fontSize: '11px', fontWeight: 600, color: COULEURS.discret, width: '100%' } },
          appareils.length === 0 ? 'Aucun appareil appairé' : 'Appareils appairés (' + String(appareils.length) + ')',
        ),
      )
      for (const appareil of appareils) {
        const enConfirmation = confirmation === appareil.empreinte
        contenu.push(
          React.createElement(
            'div',
            {
              key: appareil.empreinte,
              style: {
                display: 'flex',
                flexDirection: 'column',
                gap: '4px',
                boxSizing: 'border-box',
                width: '100%',
                padding: '7px 9px',
                borderRadius: '7px',
                background: COULEURS.couche,
              },
            },
            React.createElement('span', { style: { fontSize: '12px', color: COULEURS.texte, wordBreak: 'break-all' } }, appareil.nom),
            React.createElement(
              'span',
              { style: { fontSize: '10px', color: COULEURS.discret } },
              (appareil.portee === 'ecriture' ? 'écriture' : 'lecture') +
                ' · ' +
                dateLisible(appareil.creeLe) +
                ' · ' +
                appareil.empreinte,
            ),
            React.createElement(
              'button',
              {
                type: 'button',
                disabled: rechargement,
                onClick: () => {
                  if (enConfirmation) revoquer(appareil.empreinte)
                  else setConfirmation(appareil.empreinte)
                },
                style: { ...boutonStyle(false), alignSelf: 'flex-start', color: enConfirmation ? COULEURS.danger : COULEURS.texte },
              },
              enConfirmation ? 'Confirmer la révocation' : 'Révoquer',
            ),
          ),
        )
      }
      contenu.push(
        React.createElement(
          'div',
          { key: 'appareils-note', style: { fontSize: '10px', lineHeight: 1.4, color: COULEURS.discret, width: '100%' } },
          appareils.some((appareil) => appareil.historique === true)
            ? "Révoquer coupe CET appareil. Le jeton historique (terminal) ne revient qu'au prochain démarrage du harness."
            : 'Révoquer coupe cet appareil seulement : les autres continuent de fonctionner.',
        ),
      )

      if (message.length > 0 && etat !== 'erreur') {
        contenu.push(
          React.createElement('div', { key: 'message', style: { fontSize: '11px', color: COULEURS.alerte, width: '100%' } }, message),
        )
      }

      const actions = [
        React.createElement(
          'button',
          { key: 'regenerer', type: 'button', onClick: frapper, style: boutonStyle(true) },
          etat === 'pret' && restant <= 0 ? 'Générer un nouveau code' : 'Nouveau code',
        ),
        React.createElement('button', { key: 'fermer', type: 'button', onClick: fermer, style: boutonStyle(false) }, 'Fermer'),
      ]
      contenu.push(
        React.createElement('div', { key: 'actions', style: { display: 'flex', gap: '8px', marginTop: '2px' } }, actions),
      )

      return React.createElement(
        'div',
        { style: { display: 'inline-flex' } },
        bouton,
        React.createElement(
          'div',
          {
            onClick: fermer,
            style: {
              position: 'fixed',
              inset: 0,
              zIndex: 80,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              background: 'rgba(0,0,0,0.45)',
            },
          },
          React.createElement(
            'div',
            {
              onClick: (evenement) => evenement.stopPropagation(),
              style: {
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: '10px',
                boxSizing: 'border-box',
                maxWidth: 'min(92vw, 360px)',
                maxHeight: '88vh',
                overflowY: 'auto',
                padding: '20px',
                borderRadius: '14px',
                border: '1px solid ' + COULEURS.bord,
                background: COULEURS.fond,
                color: COULEURS.texte,
                boxShadow: '0 18px 48px rgba(0,0,0,0.4)',
              },
            },
            contenu,
          ),
        ),
      )
    }

    /** Enregistrement du panneau. Une défaillance ici ne casse rien d'autre. */
    function apply(ctx) {
      if (React === null) {
        console.error('[dsh-remote] panneau d appairage indisponible: react absent de la table de modules')
        return
      }
      const slots = ctx.slots !== undefined && ctx.slots !== null ? ctx.slots : typeof ctx.get === 'function' ? ctx.get('slots') : undefined
      if (slots === undefined || slots === null || typeof slots.inject !== 'function') {
        console.error('[dsh-remote] panneau d appairage indisponible: service slots absent')
        return
      }
      slots.inject('sidebar.footer.action', () =>
        slots.register(
          {
            name: 'sidebar.footer.action',
            id: 'dsh-remote-appairage',
          },
          BoutonAppairage,
        ),
      )
    }

    exports.inject = ['slots']
    exports.apply = apply
    // Surface de TEST, sans effet à l'exécution : elle permet à
    // `tests/bundle.test.js` d'éprouver l'encodeur RÉELLEMENT EMBARQUÉ (et non
    // une copie de laboratoire) sans rien exposer du panneau.
    exports.essai = { encodeQr: encodeQr, dureeLisible: dureeLisible }
    return module.exports
  },
})
