import DSHRemoteKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Réglages : ce qui n'est plus sur la page d'accueil.
///
/// POURQUOI CETTE FEUILLE EXISTE. L'adresse, le jeton, le test d'adresse et les
/// filtres occupaient plus de la moitié de la hauteur utile de la page
/// principale — pour des gestes qu'on fait une fois, puis plus jamais. La page
/// principale est redevenue ce qu'elle doit être : des appareils et des
/// sessions. Le reste descend d'un cran.
///
/// CE QUI N'A PAS LE DROIT D'ÊTRE PERDU EN CHEMIN. Chaque élément déplacé ici
/// corrigeait un défaut RÉEL, constaté sur l'iPhone :
///
///   - le champ du jeton est TOUJOURS visible. Il était auparavant masqué dès
///     qu'un jeton était présent, c'est-à-dire dès le PREMIER caractère saisi :
///     le champ disparaissait sous les doigts de l'utilisateur, qui ne pouvait
///     jamais terminer sa saisie ;
///   - le compte de caractères est affiché en clair. Un champ de 43 caractères
///     affiche des puces : sans ce compte, un jeton tronqué est indiscernable
///     d'un jeton complet, et le `401` qui suit accuse le serveur à tort ;
///   - le bouton « Coller » existe. 43 caractères en base64url, recopiés depuis
///     un terminal, ne se tapent pas à la main sur un clavier de téléphone ;
///   - « Tester l'adresse » dit ce qu'il a trouvé. C'est l'action qui a du sens
///     quand on a saisi une adresse à la main, et elle nomme son résultat —
///     « rien ne s'est passé » ne doit jamais être une réponse possible.
struct FeuilleReglages: View {
  @Bindable var modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // ── POURQUOI LE LIBELLÉ EST AU-DESSUS, ET NON À GAUCHE ──────────
          //
          // La disposition précédente employait `LabeledContent`, qui place le
          // libellé à gauche et le champ à droite. Sur macOS, cela donnait une
          // feuille ILLISIBLE : mesuré sur capture, l'URL `http://macmini.tail…`
          // débordait de la fenêtre, par-dessus le texte voisin — on croyait
          // voir DEUX adresses superposées, alors qu'il n'y avait qu'un champ
          // trop étroit pour ce qu'il contient.
          //
          // Une adresse de tailnet fait une quarantaine de caractères : elle a
          // besoin de la largeur entière. Le libellé passe donc au-dessus, et le
          // champ occupe la ligne — la disposition que macOS emploie lui-même
          // pour les valeurs longues.
          Label("Adresse", systemImage: modele.symboleServeur)
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            // Liaison passant par le modèle : l'adresse est mémorisée dès la
            // frappe, sans attendre une connexion réussie. C'est précisément
            // quand la connexion échoue qu'on veut retrouver son adresse.
            TextField(
              modele.adresseExemple,
              text: Binding(
                get: { modele.adresse },
                set: { modele.definirAdresse($0) }
              )
            )
            // Police à chasse fixe : une adresse se lit caractère par caractère,
            // et c'est ce qui permet de repérer une faute de frappe.
            .font(.callout.monospaced())
            .lineLimit(1)
            .autocorrectionDisabled()
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .keyboardType(.URL)
            #endif
            if !modele.adresse.isEmpty {
              Button {
                modele.oublierServeur()
              } label: {
                Image(systemName: "xmark.circle")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel("Oublier ce serveur")
            }
          }
          if let nom = modele.nomServeur, !nom.isEmpty {
            Label(nom, systemImage: modele.symboleServeur)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Adresse")
        } footer: {
          Text(
            "L'adresse découle du serveur choisi. Ce champ ne sert qu'aux cas que la découverte ne couvre pas."
          )
        }

        Section {
          // Même disposition que l'adresse, et pour la même raison : un secret
          // de 43 caractères ne tient pas dans une colonne de droite étroite.
          Label("Jeton", systemImage: "key")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 8) {
            SecureField(
              modele.jetonDisponible ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil",
              text: $modele.jetonSaisi
            )
            .font(.callout.monospaced())
            .lineLimit(1)
            .autocorrectionDisabled()
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
          // L'état du jeton, en clair : un jeton tronqué doit se voir AVANT
          // d'accuser le serveur.
          if modele.jetonDisponible {
            Label(
              modele.jetonBienForme
                ? "jeton complet (43 caractères)"
                : "jeton incomplet : \(modele.longueurJeton) caractères au lieu de 43",
              systemImage: modele.jetonBienForme ? "checkmark.seal" : "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(modele.jetonBienForme ? Color.green : Color.orange)
          }
          HStack(spacing: 12) {
            Button("Se connecter") {
              Task { await modele.connecter() }
            }
            .disabled(modele.enChargement)
            Button("Tester l'adresse") {
              Task { await modele.testerAdresse() }
            }
            .disabled(modele.enChargement || modele.adresse.isEmpty)
            if modele.enChargement { ProgressView().controlSize(.small) }
          }
          // Le résultat du test, nommé : « rien ne s'est passé » ne doit jamais
          // être une réponse possible à un appui.
          switch modele.etatAdresse {
          case .inconnu:
            EmptyView()
          case .enCours:
            Label("test de l'adresse…", systemImage: "hourglass").font(.caption)
          case let .joignable(reponses):
            Label("\(reponses) session(s) — adresse et jeton acceptés", systemImage: "checkmark.circle")
              .font(.caption)
              .foregroundStyle(.green)
          case let .injoignable(detail):
            Label(detail, systemImage: "xmark.circle")
              .font(.caption)
              .foregroundStyle(.red)
          }
        } header: {
          Text("Jeton d'appareil")
        } footer: {
          Text(
            "Le jeton est conservé au trousseau, jamais dans les préférences. Il est affiché une seule fois par le harness, au premier chargement du plugin."
          )
        }

        Section {
          // L'étiquette dit ce que le critère EST, pas ce qu'il suggère.
          //
          // « Vivantes » laissait croire à des sessions en train de travailler :
          // le propriétaire s'est étonné d'en compter dix. Or ce champ signifie
          // « chargée dans le processus du harness », c'est-à-dire prête à être
          // reprise instantanément — pas active. La nuance compte : dix sessions
          // actives serait anormal, dix sessions chargées est normal après une
          // journée de travail.
          Toggle("Chargées en mémoire seulement", isOn: $modele.filtresActifs)
          // Le suivi se voit et se commande : sans lui, les pastilles d'état
          // resteraient figées au moment du chargement, et une session qui se
          // met à travailler n'apparaîtrait jamais comme telle.
          Toggle("Suivre l'activité", isOn: $modele.suiviAutomatique)
        } header: {
          Text("Sessions")
        } footer: {
          Text(
            "« Chargées » veut dire prêtes à être reprises instantanément, pas en train de travailler."
          )
        }
      }
      .navigationTitle("Réglages")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Terminé") { fermer() }
        }
      }
    }
  }
}
