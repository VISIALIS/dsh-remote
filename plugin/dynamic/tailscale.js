/**
 * LA DÉCOUVERTE DU TAILNET : quelles machines sont en ligne, et lesquelles
 * peuvent héberger DSH.
 *
 * POURQUOI CE FICHIER EXISTE. Ce bloc vivait au milieu d'un fichier de 1 637
 * lignes, mêlé aux routes et au cache. Il ne dépend pourtant que d'une chose :
 * le binaire LOCAL de Tailscale. Le sortir rend ses deux fonctions d'analyse
 * éprouvables — `analyserTailnet` et `raisonCourte` sont PURES, et elles portent
 * des règles mesurées (voir plus bas).
 *
 * HORS DSH : la découverte lance le binaire local (`node:child_process`, argv
 * fixe, sans shell). Ce n'est ni une API DSH ni une API distante : c'est un état
 * déjà présent sur la machine. Si le binaire manque ou refuse de répondre, la
 * route rend une liste vide AVEC sa raison, et le reste du plugin fonctionne.
 */

import { execFile } from 'node:child_process'
import { constants as constantesFS } from 'node:fs'
import { access } from 'node:fs/promises'
import { join } from 'node:path'

// Candidats, essayés DANS CET ORDRE JUSQU'À UN SUCCÈS — et non jusqu'au premier
// fichier exécutable. La distinction est mesurée : sur cette machine,
// `/usr/local/bin/tailscale` est un lien symbolique vers le binaire de
// l'application, et le lancer par ce lien échoue (« The current bundleIdentifier
// is unknown to the registry ») alors que le binaire direct réussit. Un lien
// perd l'identité de bundle dont le CLI a besoin pour joindre l'application.
const CHEMINS_TAILSCALE = [
  '/Applications/Tailscale.app/Contents/MacOS/Tailscale',
  '/opt/homebrew/bin/tailscale',
  '/usr/local/bin/tailscale',
]

const DELAI_TAILSCALE_MS = 8000
const PLAFOND_SORTIE_TAILSCALE = 4 * 1024 * 1024

/**
 * Un Mac tel que la découverte le propose. `local` marque l'hôte qui répond —
 * c'est-à-dire celui qui exécute cette instance, information que seul l'hôte
 * connaît.
 * @typedef {{nom: string, nomDNS: string, enLigne: boolean, local: boolean}} MacTrouve
 */

/**
 * Analyse la sortie de `tailscale status --json`.
 *
 * Séparée de l'exécution pour être éprouvable sans lancer de processus, comme
 * côté Swift. Ne retient que `Self` et `Peer`, et seulement les machines macOS :
 * proposer un PC Windows ou un iPhone comme serveur DSH serait une promesse que
 * l'installation ne peut pas tenir.
 *
 * @param {string} sortie
 * @returns {MacTrouve[] | null} `null` si la sortie n'a pas la forme attendue.
 */
export function analyserTailnet(sortie) {
  const racine = JSON.parse(sortie)
  if (racine === null || typeof racine !== 'object') return null

  const trouves = []
  const retenir = (objet, local) => {
    if (objet === null || typeof objet !== 'object') return
    if (objet.OS !== 'macOS') return
    const dns = typeof objet.DNSName === 'string' ? objet.DNSName : ''
    if (dns.length === 0) return
    // Le point final est la forme absolue du DNS : on le retire pour que le nom
    // soit directement utilisable comme adresse.
    const nomDNS = dns.endsWith('.') ? dns.slice(0, -1) : dns
    const nom = typeof objet.HostName === 'string' && objet.HostName.length > 0 ? objet.HostName : nomDNS
    trouves.push({ nom, nomDNS, enLigne: local ? true : objet.Online === true, local })
  }

  retenir(racine.Self, true)
  if (racine.Peer !== null && typeof racine.Peer === 'object') {
    for (const valeur of Object.values(racine.Peer)) retenir(valeur, false)
  }

  // En ligne d'abord, puis par nom : l'ordre doit être stable d'un appel à
  // l'autre, sinon la liste semble sauter sous les yeux de l'utilisateur.
  return trouves.sort((gauche, droite) => {
    if (gauche.enLigne !== droite.enLigne) return gauche.enLigne ? -1 : 1
    return gauche.nom.localeCompare(droite.nom, 'fr')
  })
}

/**
 * Réduit un message d'erreur à une ligne courte, sans retour à la ligne.
 *
 * Le diagnostic est utile — il distingue « binaire absent » de « Tailscale
 * refuse de répondre » — mais il part dans une réponse HTTP : il est tronqué et
 * débarrassé de ses sauts de ligne pour rester un champ de texte, pas un journal.
 */
export function raisonCourte(texte) {
  const ligne = String(texte ?? '').split('\n').find((element) => element.trim().length > 0) ?? ''
  const propre = ligne.replace(/\s+/g, ' ').trim()
  return propre.length > 120 ? propre.slice(0, 120) : propre
}

/**
 * Lance un candidat et rend `{macs, raison}` : `macs` vaut `null` en cas d'échec,
 * et `raison` porte alors une explication courte.
 * @param {string} binaire
 */
export function lancerTailscale(binaire) {
  return new Promise((resolve) => {
    execFile(
      binaire,
      ['status', '--json'],
      { timeout: DELAI_TAILSCALE_MS, maxBuffer: PLAFOND_SORTIE_TAILSCALE, windowsHide: true, encoding: 'utf8' },
      (erreur, sortie, erreurs) => {
        if (erreur !== null && erreur !== undefined) {
          if (erreur.killed === true) return resolve({ macs: null, raison: 'delai depasse' })
          if (erreur.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') return resolve({ macs: null, raison: 'sortie trop volumineuse' })
          return resolve({ macs: null, raison: raisonCourte(erreurs) || raisonCourte(erreur.message) })
        }
        let macs = null
        try {
          macs = analyserTailnet(sortie)
        } catch {
          return resolve({ macs: null, raison: 'sortie illisible' })
        }
        if (macs === null) return resolve({ macs: null, raison: 'sortie inattendue' })
        resolve({ macs, raison: null })
      },
    )
  })
}

/**
 * Liste les Macs du tailnet, vus depuis CETTE machine.
 *
 * Ne lève jamais : une découverte impossible rend une liste vide AVEC sa raison,
 * parce qu'une liste vide sans explication est indébogable — on ne sait pas si
 * le binaire manque, si Tailscale est arrêté ou si la sortie est illisible, et
 * ces trois causes ne se corrigent pas de la même façon.
 *
 * @returns {Promise<{macs: MacTrouve[], diagnostic: string | null}>}
 */
export async function decouvrirMacs() {
  const maison = typeof process.env.HOME === 'string' ? process.env.HOME : ''
  const candidats = CHEMINS_TAILSCALE.slice()
  if (maison.length > 0) candidats.splice(1, 0, join(maison, '.local', 'bin', 'tailscale'))

  const raisons = []
  for (const binaire of candidats) {
    try {
      await access(binaire, constantesFS.X_OK)
    } catch {
      continue
    }
    const { macs, raison } = await lancerTailscale(binaire)
    if (macs !== null) {
      return { macs, diagnostic: macs.length === 0 ? 'aucun Mac macOS dans le tailnet' : null }
    }
    raisons.push(raison)
  }

  if (raisons.length === 0) return { macs: [], diagnostic: 'binaire tailscale introuvable' }
  return { macs: [], diagnostic: 'tailscale muet: ' + raisons[0] }
}
