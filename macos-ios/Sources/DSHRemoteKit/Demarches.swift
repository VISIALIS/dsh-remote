import SwiftUI

// LES DEUX DÉMARCHES D'UN MAC QUI NE SERT PAS ENCORE DSH.
//
// POURQUOI ELLES SONT SORTIES DE LA PAGE D'UN SERVEUR. Elles y étaient écrites
// pour une machine précise, puis la page « Ajouter un serveur » a eu besoin des
// mêmes — mot pour mot, puisque le travail à faire sur le Mac est identique qu'on
// le connaisse déjà ou non. Les dupliquer aurait fait diverger deux procédures
// que l'utilisateur compare. Depuis la refonte, les deux pages sont UNE SEULE vue
// (`FicheServeur`) : ces démarches n'ont donc plus qu'un lecteur, et c'est tant
// mieux.
//
// ELLES SONT SÉPARÉES PARCE QUE LA CAUSE DIFFÈRE, et que confondre les deux
// envoie chercher la panne au mauvais endroit. Mesuré sur MacMini : le port 80
// était publié (la racine répondait « dsh web authentication required ») mais
// `/dsh-remote/v1/sante` rendait `404` — le plugin n'y était pas chargé. Donner
// dans ce cas les commandes Tailscale serait à côté : le tailnet et la
// publication vont bien.
//
// ET L'ORDRE ENTRE LES DEUX EST CELUI DE LA MESURE : « rien ne répond » ne veut
// pas dire « le plugin manque », mais « DSH ne répond pas » — donc, souvent, « DSH
// n'est pas lancé ». C'est pourquoi l'installation de DSH elle-même est enseignée
// par la PREMIÈRE démarche, celle du port, et non par celle du plugin : une
// machine qui n'a pas DSH ne peut pas rendre de `404`.

/// LA DÉMARCHE QUAND RIEN N'ÉCOUTE SUR LE PORT 80.
///
/// POURQUOI ELLE COMMENCE PAR L'INSTALLATION DE DSH. Elle ne le faisait pas, et
/// c'était le trou de la procédure : elle faisait publier un port à quelqu'un qui
/// n'avait peut-être rien à publier. La commande d'installation est VÉRIFIÉE à la
/// source — la page officielle du harness, « Quick start : Install Node.js, then
/// launch the Web UI with npx » —, et elle n'est écrite nulle part ailleurs dans
/// l'application : le README du paquet publié `@deepseek-ai/dsh` ne contient
/// aucune section d'installation.
struct DemarchePublicationPort: View {
  var body: some View {

    VStack(alignment: .leading, spacing: 8) {
      Label { T("Aucun service n'écoute sur le port 80 de cette machine. Le tailnet, lui, fonctionne : la machine répond.") } icon: { Image(systemName: "network.slash") }
      .font(.footnote)
      .foregroundStyle(EtatVisuel.attention.couleur)
      .fixedSize(horizontal: false, vertical: true)

      // 1. DSH DOIT TOURNER. C'est la première chose à vérifier, et elle manquait.
      T("1. Sur cette machine-là, DSH doit tourner. S'il n'y est pas — Node.js est requis :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "npx @deepseek-ai/dsh web")

      // 2. PUIS ON LE PUBLIE. Les commandes se copient, elles ne se lisent pas :
      // elles sont destinées à être tapées sur l'AUTRE Mac. La commande a été
      // vérifiée sur cette machine — `tailscale serve status --json` est resté
      // IDENTIQUE avant et après.
      T("2. Publiez ensuite son port 80 sur le tailnet :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve --bg --http=80 http://127.0.0.1:3080")
      T("Et vérifiez, sur cette machine-là :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve status")

      T("Le plugin `dsh-remote` doit AUSSI y être chargé : publier DSH ne suffit pas. S'il manque, l'étape 4 donne sa démarche d'installation.")
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

/// LA DÉMARCHE QUAND LA MACHINE RÉPOND, MAIS QUE LE PLUGIN N'Y EST PAS.
///
/// POURQUOI UNE DÉMARCHE, ET POURQUOI ELLE EST DEVENUE UN PROMPT. « Le plugin n'est
/// pas chargé » ne dit pas quoi faire : le charger demande de déposer le dépôt sur
/// la machine, de le DÉCLARER dans le profil du harness, puis de vérifier — et
/// cette suite d'étapes est exactement ce qu'un agent fait bien, sur la machine où
/// il tourne déjà.
///
/// LA CONSIGNE EST COURTE, ET ELLE RENVOIE AU README. C'est le point qui a changé :
/// elle portait le bloc YAML entier, recopié de `plugin/README.md`.
/// Deux copies d'une même vérité finissent par diverger — et celle-ci décrit une
/// ligne de configuration dont dépend tout le reste. Le prompt dit donc OÙ est la
/// vérité, et l'agent la lit sur place, dans la version du dépôt qu'il vient de
/// cloner.
///
/// ELLE NE DEMANDE PAS DE REDÉMARRAGE, ET CE N'EST PAS UN OUBLI. Le profil est en
/// `patchReload: live` : ajouter la ligne au patch est rechargé à chaud, et les
/// routes apparaissent en quelques secondes (mesuré, écrit au README du plugin).
/// Ce qui reste à constater — P11 du même README — est l'apparition du BOUTON du
/// panneau sans redémarrage : d'où la phrase qui demande de recharger l'onglet,
/// puis de relancer le harness SI le bouton n'est toujours pas là. On ne fait donc
/// redémarrer personne « au cas où » : la machine qui n'a rien à publier n'a rien
/// à redémarrer.
struct DemarcheInstallationPlugin: View {
  var body: some View {

    VStack(alignment: .leading, spacing: 8) {
      Label { T("Le plugin `dsh-remote` n'est pas installé sur cette machine. DSH y tourne et son port 80 est publié — mais rien n'y expose DSH Remote.") } icon: { Image(systemName: "puzzlepiece.extension") }
      .font(.footnote)
      .foregroundStyle(EtatVisuel.attention.couleur)
      .fixedSize(horizontal: false, vertical: true)

      // LE PROMPT SE COLLE SUR LE MAC — et l'application le dit, parce que c'est
      // ici qu'on pourrait se tromper : cette page s'affiche sur l'appareil, et
      // la commande, elle, se tape ailleurs.
      T("Sur le Mac qui héberge DSH — pas sur cet appareil : ouvrez une session DSH sur ce Mac, et collez-lui ceci :")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      LigneCommande(
        commande: """
          Installe le plugin dsh-remote dans le profil web de ce harness :
          clone https://github.com/VISIALIS/dsh-remote, puis suis la section
          « Chargement » de plugin/README.md — c'est elle qui porte la
          ligne exacte à ajouter à ~/.dsh/profiles/web/cordis.patch.yml.
          Ne redémarre pas le harness : le profil recharge ce patch à chaud.
          Vérifie ensuite que
          curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:3080/dsh-remote/v1/sante
          rend 401 ou 200 (401 = aucun jeton présenté, c'est normal), et dis-moi où
          se trouve la fonction d'appairage dans l'interface web.
          """,
        libelle: "prompt")

      // LA VÉRIFICATION EST FOURNIE, ET ELLE MARCHE SANS JETON : mesuré, la route
      // répond 401 quand aucun jeton n'est présenté, et 200 quand il l'est. Les
      // deux prouvent que le plugin est chargé — ce qui est la question ici.
      T("Si vous préférez vérifier vous-même, depuis ce Mac : `401` ou `200` veut dire que le plugin répond (`401` = jeton absent, c'est normal).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(
        commande: "curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1:3080/dsh-remote/v1/sante")

      T("Le bouton d'appairage est en bas de la barre latérale de l'interface web, sous le nom « DSH Remote ». S'il n'apparaît pas, rechargez l'onglet — et s'il manque encore, relancez `dsh web`.")
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
