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

  @ViewBuilder
  private var diagnostic: some View {
    if let erreur = modele.erreur {
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
        if modele.serveurSansDsh { remede }
      }
    }
  }

  /// Ce qu'il faut faire SUR CETTE MACHINE, avec les commandes à recopier.
  private var remede: some View {
    VStack(alignment: .leading, spacing: 8) {
      // LE FAIT DIFFÈRE SELON LE CAS, ET LE TEXTE LE DIT.
      //
      // Port vide (`-1004`) : la machine répond, rien n'écoute. Port occupé par
      // autre chose (un `404` de `tailscale serve`, mesuré sur MacMini) : la
      // machine répond, mais pas DSH Remote. Écrire « aucun service ne répond »
      // dans le second cas serait faux — quelque chose a répondu.
      Label(
        modele.portOccupeParAutreChose
          ? "Ce Mac répond, mais pas DSH Remote : le plugin `dsh-remote` n'y est pas chargé (ou `tailscale serve` n'y publie pas l'instance)."
          : "Aucun service n'écoute sur le port 80 de ce Mac. Le tailnet, lui, fonctionne : la machine répond.",
        systemImage: "network.slash"
      )
      .font(.footnote)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)

      // LES COMMANDES SE COPIENT, ELLES NE SE LISENT PAS.
      //
      // Elles sont destinées à être tapées sur l'AUTRE Mac — celui qui ne publie
      // rien. Les afficher en texte monospace obligeait à les sélectionner à la
      // main, sur un téléphone, au milieu d'un paragraphe.
      //
      // LA COMMANDE A ÉTÉ CORRIGÉE, ET VÉRIFIÉE : l'ancienne
      // (`tailscale serve --bg 80 http://127.0.0.1:3080`) était fausse — `--bg`
      // ne prend pas de port, et `serve` n'accepte qu'une cible. Celle-ci a été
      // passée sur cette machine et `tailscale serve status --json` est resté
      // IDENTIQUE avant et après.
      //
      // LE PLUGIN FAIT PARTIE DE LA RÉPONSE, ET C'EST MESURÉ AINSI : sur MacMini,
      // le port 80 était bien publié (la racine répondait « dsh web
      // authentication required ») mais `/dsh-remote/v1/sante` rendait `404` —
      // le plugin n'y était pas chargé.
      Text("Le plugin `dsh-remote` doit aussi y être chargé (voir le README du plugin) : publier DSH ne suffit pas.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("Sur ce Mac-là, publiez l'instance DSH :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve --bg --http=80 http://127.0.0.1:3080")
      Text("Vérifiez ensuite, sur ce Mac-là :")
        .font(.caption)
        .foregroundStyle(.secondary)
      LigneCommande(commande: "tailscale serve status")
      Text("Le jeton n'est pas en cause ici : rien n'a pu être joint. Attention, il est PROPRE À CHAQUE HÔTE — celui de ce Mac ne vaudra pas pour un autre.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }
}
