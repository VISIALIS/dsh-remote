// REFERENCE FIGEE DE L'ENCODEUR QR — aucun test ici, c'est une DONNEE.
//
// D'OU VIENT CE FICHIER, ET POURQUOI IL EXISTE ENCORE. Ce bloc est le texte
// VERBATIM de l'encodeur de `plugins/share-qr/dynamic/client.js` (lignes 17 a
// 324), copie le 14 septembre 2026, juste avant la suppression du plugin
// `share-qr`. `plugins/dsh-remote/dynamic/client.js` embarque une copie assumee
// de ce meme bloc (REGLE #2 : un plugin est autonome) ; `bundle.test.js`
// comparait cette copie a son origine, et cette origine a quitte le depot.
//
// LA COMPARAISON N'A PAS ETE SUPPRIMEE, ELLE A ETE FIGEE. Sans ce fichier, le
// test qui empeche la copie de deriver disparaitrait avec le plugin, et plus rien
// ne dirait qu'un encodage corrige d'un cote ne l'est pas de l'autre. Ici la
// reference ne bouge plus : toute modification du bloc embarque fait echouer le
// test, ce qui rend la re-copie deliberee au lieu d'etre un oubli.
//
// NE PAS REFORMATER CE BLOC : le test le compare caractere pour caractere.
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
