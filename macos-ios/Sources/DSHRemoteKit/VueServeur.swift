import DSHRemoteKit
import SwiftUI

/// La page d'un serveur : ce qu'il est, ce qu'on peut faire avec lui, et quoi
/// faire quand il ne publie rien.
///
/// POURQUOI CETTE PAGE EXISTE, ET CE QU'ELLE DÉPLACE. Le panneau latéral portait
/// l'état des machines **et** le diagnostic complet, jusqu'aux commandes à
/// recopier sur l'autre Mac. Résultat : une colonne encombrée, où le message le
/// plus long prenait la place des sessions — il fallait faire défiler pour voir
/// son propre travail.
///
/// Le diagnostic appartient à la MACHINE : il vit donc sur SA page, qu'on ouvre
/// en touchant son icône. Le panneau latéral garde ce qui se lit d'un coup
/// d'œil : la pastille, la légende, le nom.
struct VueServeur: View {
  @Bindable var modele: ModeleApp
  /// La machine affichée, résolue à chaque rendu par `VuePrincipale`.
  let serveur: ServeurMac
  var ouvrirReglages: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        enTete
        adresseEtActions
        session
        // La bascule de serveur se DIT : changer la machine de l'utilisateur
        // sans le prévenir serait une substitution silencieuse. L'avis est ici
        // plutôt qu'à gauche : il concerne une machine, et c'est sa page.
        if let ajuste = modele.choixAjuste {
          Label(ajuste, systemImage: "arrow.triangle.swap")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        diagnostic
      }
      .padding(24)
      .frame(maxWidth: 680, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(serveur.nom)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
  }

  // MARK: - En-tête

  private var enTete: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: serveur.symbole)
        .font(.system(size: 34))
        .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
        .frame(width: 46)
      VStack(alignment: .leading, spacing: 3) {
        Text(serveur.nom).font(.title2)
        Text(etatLisible)
          .font(.callout)
          .foregroundStyle(serveur.enLigne ? Color.green : Color.secondary)
      }
      Spacer()
      if modele.serveurChoisi == serveur {
        Label("serveur courant", systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(Color.accentColor)
      }
    }
  }

  /// L'état en clair, avec ce qui est SU et ce qui ne l'est pas.
  ///
  /// « Vérification… » n'est pas une décoration : tant que la sonde n'a pas
  /// rendu son verdict, on ne sait pas si la machine sert DSH, et le dire est
  /// plus honnête que de laisser croire à un « non ».
  private var etatLisible: String {
    guard serveur.enLigne else { return "hors ligne sur le tailnet" }
    switch modele.sertDsh(serveur) {
    case true: return serveur.estLocal ? "en ligne · DSH · hôte interrogé" : "en ligne · DSH"
    case false: return "en ligne · pas de DSH"
    case nil: return "en ligne · vérification en cours"
    }
  }

  // MARK: - Adresse et actions

  private var adresseEtActions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Adresse")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(serveur.adresse)
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        Button {
          Task { await modele.choisirEtConnecter(serveur) }
        } label: {
          Label("Se connecter", systemImage: "bolt.horizontal")
        }
        .buttonStyle(.borderedProminent)
        .disabled(modele.enChargement)

        Button {
          Task { await modele.testerAdresse() }
        } label: {
          Label("Tester", systemImage: "stethoscope")
        }
        .disabled(modele.enChargement)

        if modele.enChargement { ProgressView().controlSize(.small) }
      }

      jeton
    }
  }

  /// Le suivi et le filtre de CETTE machine.
  ///
  /// POURQUOI ICI ET NON DANS LES RÉGLAGES GÉNÉRAUX — le propriétaire l'a
  /// demandé, et il a raison : les deux portent sur la connexion à une machine.
  /// Le suivi décide si l'on interroge CE serveur toutes les trois secondes ; le
  /// filtre décide ce qu'on affiche de SA liste. Les garder globaux faisait
  /// hériter chaque serveur des choix faits pour le précédent.
  ///
  /// La note dit aussi ce qui se passe si la machine n'est pas celle à laquelle
  /// on est connecté : le réglage est enregistré, et s'appliquera à la
  /// connexion. Un interrupteur doit dire quand il agit.
  private var session: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle(
        "Suivre l'activité",
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).suivi },
          set: { actif in modele.definirPreferences(pour: serveur.adresse) { $0.suivi = actif } }))
      Toggle(
        "Chargées en mémoire seulement",
        isOn: Binding(
          get: { modele.preferences(pour: serveur.adresse).chargeesSeulement },
          set: { actif in
            modele.definirPreferences(pour: serveur.adresse) { $0.chargeesSeulement = actif }
          }))

      Text(
        modele.serveurVise?.id == serveur.id
          ? "Ces deux réglages valent pour cet hôte, et s'appliquent maintenant : c'est le serveur connecté. « Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler."
          : "Ces deux réglages valent pour cet hôte et seront appliqués quand vous vous y connecterez."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Le jeton d'appareil, SUR LA PAGE DE LA MACHINE.
  ///
  /// POURQUOI ICI, ET NON DANS LES RÉGLAGES GÉNÉRAUX — mesuré. Le jeton est tiré
  /// par CHAQUE hôte et rangé dans son coffre : deux Macs qui hébergent le plugin
  /// ont deux jetons distincts, et celui d'une machine ne vaut pas pour une
  /// autre. Un réglage « général » qui ne vaut que pour un hôte serait un
  /// mensonge d'endroit. C'est aussi la première chose qu'on soupçonne quand une
  /// machine répond mais refuse — et l'avoir soupçonné à tort a déjà coûté du
  /// temps.
  private var jeton: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Jeton d'appareil de cet hôte")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        SecureField(
          modele.jetonDisponible ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil",
          // Guardé dès la frappe POUR CET HÔTE : un jeton collé puis abandonné
          // serait perdu, alors qu'il vient d'être recopié.
          text: Binding(get: { modele.jetonSaisi }, set: { modele.definirJeton($0) })
        )
        .font(.callout.monospaced())
        .lineLimit(1)
        .autocorrectionDisabled()
        .layoutPriority(1)
        #if os(iOS)
          .textInputAutocapitalization(.never)
        #endif
        Button {
          modele.collerLeJeton()
        } label: {
          Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Coller le jeton depuis le presse-papier")
        if modele.jetonDisponible {
          Button {
            modele.effacerJeton()
          } label: {
            Image(systemName: "xmark.circle")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Effacer le jeton")
        }
      }
      Label(
        modele.jetonBienForme
          ? "jeton complet (43 caractères)"
          : "jeton incomplet : \(modele.longueurJeton) caractères au lieu de 43",
        systemImage: modele.jetonBienForme ? "checkmark.seal" : "exclamationmark.triangle"
      )
      .font(.caption)
      .foregroundStyle(modele.jetonBienForme ? Color.green : Color.orange)

      // Un `401` propose l'action qui RÉPARE, à portée de pouce : le champ est
      // juste au-dessus. Le rappel n'apparaît que pour cette cause-là — une
      // adresse injoignable ne se règle pas ici.
      if modele.jetonRefuse {
        Label(
          "Le service a refusé ce jeton. Collez celui de CET hôte : chaque machine a le sien.",
          systemImage: "key"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }

      Text("Il s'affiche une seule fois, dans la sortie du harness, au premier chargement du plugin sur cette machine. Il n'est jamais renvoyé par une route.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Diagnostic

  /// La cause, POUR CETTE MACHINE.
  private var cause: CauseSansDsh? { modele.causeSansDsh(serveur) }

  @ViewBuilder
  private var diagnostic: some View {
    // ── LE DIAGNOSTIC APPARTIENT À LA MACHINE, PAS À LA CONNEXION ───────────
    //
    // Défaut corrigé : le bloc lisait l'erreur de la CONNEXION EN COURS. Sur la
    // page de MacMini alors que l'application était connectée ailleurs, il n'y
    // avait donc AUCUN remède ; et connecté à MacMini, il pouvait en donner un
    // qui parlait d'une autre cause. La cause vient maintenant de ce qu'on a
    // mesuré SUR cette machine — la sonde pour celles qu'on ne vise pas, la
    // connexion pour celle qu'on vise.
    if cause != nil {
      remede
    } else if let erreur = modele.erreur, modele.serveurVise?.id == serveur.id {
      VStack(alignment: .leading, spacing: 12) {
        // LE PAVÉ TECHNIQUE N'EST PAS AFFICHÉ QUAND LA CAUSE EST CONNUE.
        //
        // `-1004` produit une phrase de transport d'une dizaine de lignes
        // (« NSURLErrorDomain … | sous-jacent: kCFErrorDomainCFNetwork … |
        // CAUSE: rien n'écoute sur cet hôte et ce port ») qui redisait, en rouge
        // et en charabia, ce que l'encadré ci-dessous dit en une ligne ET
        // répare. On l'occulte donc dans ce seul cas : ailleurs, il est le seul
        // diagnostic disponible — et il reste dans `diagnostic.json`.
        if !modele.serveurSansDsh {
          Label(erreur, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }

        // ── Le piège du Mac qui ne publie rien ─────────────────────────────
        //
        // La découverte liste TOUS les Macs du tailnet : elle dit qu'ils sont en
        // ligne, pas qu'ils publient DSH. En choisir un qui ne publie rien donne
        // `-1004`, et le propriétaire cherche alors la panne du côté de son
        // jeton — observé en vrai.
      }
    }
  }

  /// Ce qu'il faut faire SUR CETTE MACHINE, avec ce qui se recopie.
  ///
  /// DEUX CAUSES, DEUX DÉMARCHES — et les confondre envoie chercher la panne au
  /// mauvais endroit. Mesuré sur MacMini : le port 80 était publié (la racine
  /// répondait « dsh web authentication required ») mais `/dsh-remote/v1/sante`
  /// rendait **404** — le plugin n'y était pas chargé. Dans ce cas, donner les
  /// commandes Tailscale serait à côté : le tailnet et la publication vont bien.
  private var remede: some View {
    VStack(alignment: .leading, spacing: 8) {
      // `pluginAbsent` : la machine répond, mais pas DSH Remote — c'est le cas
      // mesuré sur MacMini. Sinon, rien n'écoute sur le port 80.
      if cause == .pluginAbsent {
        demarcheDininstallation
      } else {
        demarcheDePublication
      }
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }

  /// LE CAS MESURÉ : la machine répond, mais DSH Remote n'y est pas installé.
  ///
  /// POURQUOI UNE DÉMARCHE ET PAS UNE PHRASE. « Le plugin n'est pas chargé » ne
  /// dit pas quoi faire : le charger demande de déposer le dépôt sur la machine,
  /// de le DÉCLARER dans le profil du harness, puis de RELANCER — et le
  /// redémarrage n'est pas une formalité, puisque le code d'un plugin n'est pas
  /// rechargé à chaud (mesuré, et écrit dans le README du plugin).
  private var demarcheDininstallation: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        "Le plugin `dsh-remote` n'est pas installé sur ce Mac. DSH y tourne et son port 80 est publié — mais rien n'y expose DSH Remote.",
        systemImage: "puzzlepiece.extension"
      )
      .font(.footnote)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)

      Text("1. Avoir le dépôt `dsh-plugins` sur ce Mac, et y prendre `plugins/dsh-remote`.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Text("2. Déclarer le plugin dans `~/.dsh/profiles/web/cordis.patch.yml` :")
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

      Text("3. Relancer le harness sur ce Mac — ici `dsh web`. Le CODE d'un plugin n'est pas rechargé à chaud : sans redémarrage, l'ancien processus continue de répondre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(commande: "dsh web")

      // LA VÉRIFICATION EST FOURNIE, ET ELLE MARCHE SANS JETON : mesuré, la route
      // répond 401 quand aucun jeton n'est présenté, et 200 quand il l'est. Les
      // deux prouvent que le plugin est chargé — ce qui est la question ici.
      Text("Vérifiez sur ce Mac : `401` ou `200` veut dire que le plugin répond (`401` = jeton absent, c'est normal).")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      LigneCommande(
        commande: "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3080/dsh-remote/v1/sante")

      Text("Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de ce Mac ne vaudra pas pour un autre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// L'AUTRE CAS : rien n'écoute sur le port 80 — c'est la publication qui manque.
  private var demarcheDePublication: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        "Aucun service n'écoute sur le port 80 de ce Mac. Le tailnet, lui, fonctionne : la machine répond.",
        systemImage: "network.slash"
      )
      .font(.footnote)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)

      // LES COMMANDES SE COPIENT, ELLES NE SE LISENT PAS : elles sont destinées à
      // être tapées sur l'AUTRE Mac. La commande a été vérifiée sur cette
      // machine — `tailscale serve status --json` est resté IDENTIQUE avant et
      // après.
      Text("Sur ce Mac-là, publiez l'instance DSH :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve --bg --http=80 http://127.0.0.1:3080")
      Text("Vérifiez ensuite, sur ce Mac-là :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve status")
      Text("Le plugin `dsh-remote` doit AUSSI y être chargé : publier DSH ne suffit pas. S'il manque, la page de ce Mac donnera sa démarche d'installation.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de ce Mac ne vaudra pas pour un autre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
