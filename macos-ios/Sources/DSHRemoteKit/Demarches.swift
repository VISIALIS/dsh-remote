import SwiftUI

// LES DEUX DÉMARCHES D'UN MAC QUI NE SERT PAS ENCORE DSH.
//
// POURQUOI ELLES SONT SORTIES DE LA PAGE D'UN SERVEUR. Elles y étaient écrites
// pour une machine précise, puis la page « Ajouter un serveur » a eu besoin des
// mêmes — mot pour mot, puisque le travail à faire sur le Mac est identique qu'on
// le connaisse déjà ou non. Les dupliquer aurait fait diverger deux procédures
// que l'utilisateur compare.
//
// ELLES SONT SÉPARÉES PARCE QUE LA CAUSE DIFFÈRE, et que confondre les deux
// envoie chercher la panne au mauvais endroit. Mesuré sur MacMini : le port 80
// était publié (la racine répondait « dsh web authentication required ») mais
// `/dsh-remote/v1/sante` rendait `404` — le plugin n'y était pas chargé. Donner
// dans ce cas les commandes Tailscale serait à côté : le tailnet et la
// publication vont bien.

/// LA DÉMARCHE QUAND LA MACHINE RÉPOND, MAIS QUE LE PLUGIN N'Y EST PAS.
///
/// POURQUOI UNE DÉMARCHE ET PAS UNE PHRASE. « Le plugin n'est pas chargé » ne dit
/// pas quoi faire : le charger demande de déposer le dépôt sur la machine, de le
/// DÉCLARER dans le profil du harness, puis de RELANCER — et le redémarrage n'est
/// pas une formalité, puisque le code d'un plugin n'est pas rechargé à chaud
/// (mesuré, et écrit dans le README du plugin).
struct DemarcheInstallationPlugin: View {
  var body: some View {

    VStack(alignment: .leading, spacing: 8) {
      Label { T("Le plugin `dsh-remote` n'est pas installé sur cette machine. DSH y tourne et son port 80 est publié — mais rien n'y expose DSH Remote.") } icon: { Image(systemName: "puzzlepiece.extension") }
      .font(.footnote)
      .foregroundStyle(EtatVisuel.attention.couleur)
      .fixedSize(horizontal: false, vertical: true)

      T("1. Avoir le dépôt `dsh-plugins` sur cette machine, et y prendre `plugins/dsh-remote`.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      T("2. Déclarer le plugin dans `~/.dsh/profiles/web/cordis.patch.yml` :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      // LE CHEMIN EST UN ESPACE RÉSERVÉ, ET C'EST DIT : sur l'autre Mac, le dépôt
      // n'est pas au même endroit. Un chemin d'exemple recopié tel quel ferait
      // échouer le chargement sans dire pourquoi.
      LigneCommande(
        commande: """
          - insert:
              - id: dsh-remote
                name: 'file:///CHEMIN/DU/DEPOT/plugins/dsh-remote/dynamic/host.js'
                config:
                  journaliser: true
          """,
        libelle: "bloc")

      T("3. Relancer le harness sur cette machine — ici `dsh web`. Le CODE d'un plugin n'est pas rechargé à chaud : sans redémarrage, l'ancien processus continue de répondre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "dsh web")

      // LA VÉRIFICATION EST FOURNIE, ET ELLE MARCHE SANS JETON : mesuré, la route
      // répond 401 quand aucun jeton n'est présenté, et 200 quand il l'est. Les
      // deux prouvent que le plugin est chargé — ce qui est la question ici.
      T("Vérifiez sur cette machine : `401` ou `200` veut dire que le plugin répond (`401` = jeton absent, c'est normal).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(
        commande: "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/dsh-remote/v1/sante")

      T("Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de cette machine ne vaudra pas pour un autre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// LA DÉMARCHE QUAND RIEN N'ÉCOUTE SUR LE PORT 80 — c'est la publication qui manque.
struct DemarchePublicationPort: View {
  var body: some View {

    VStack(alignment: .leading, spacing: 8) {
      Label { T("Aucun service n'écoute sur le port 80 de cette machine. Le tailnet, lui, fonctionne : la machine répond.") } icon: { Image(systemName: "network.slash") }
      .font(.footnote)
      .foregroundStyle(EtatVisuel.attention.couleur)
      .fixedSize(horizontal: false, vertical: true)

      // LES COMMANDES SE COPIENT, ELLES NE SE LISENT PAS : elles sont destinées à
      // être tapées sur l'AUTRE Mac. La commande a été vérifiée sur cette
      // machine — `tailscale serve status --json` est resté IDENTIQUE avant et
      // après.
      T("Sur cette machine-là, publiez l'instance DSH :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve --bg --http=80 http://127.0.0.1:3080")
      T("Vérifiez ensuite, sur cette machine-là :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve status")
      T("Le plugin `dsh-remote` doit AUSSI y être chargé : publier DSH ne suffit pas. S'il manque, la page de cette machine donnera sa démarche d'installation.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      T("Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de cette machine ne vaudra pas pour un autre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
