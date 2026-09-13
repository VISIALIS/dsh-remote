import DSHRemoteKit
import SwiftUI

/// Saisie manuelle d'une adresse de serveur : le chemin des cas que la
/// découverte ne couvre pas.
///
/// POURQUOI CETTE FEUILLE EXISTE SÉPARÉMENT. L'adresse vivait dans les réglages
/// généraux, avec le jeton. Elle concerne pourtant **une machine**, pas
/// l'application : quand la découverte ne rend rien — aucun Mac ne publie, ou
/// l'iPhone n'a encore joint personne — on veut saisir une adresse et ESSAYER,
/// pas ouvrir un écran de configuration. Cette feuille ne fait que cela.
///
/// La distinction n'est pas cosmétique : les réglages généraux ne contiennent
/// plus rien de ce qui dépend d'une machine, et cette feuille-ci n'existe que
/// pendant qu'on saisit.
struct FeuilleAdresse: View {
  @Bindable var modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // Liaison passant par le modèle : l'adresse est mémorisée dès la
          // frappe, sans attendre une connexion réussie. C'est précisément quand
          // la connexion échoue qu'on veut retrouver son adresse.
          TextField(
            modele.adresseExemple,
            text: Binding(
              get: { modele.adresse },
              set: { modele.definirAdresse($0) }
            )
          )
          // Chasse fixe : une adresse se lit caractère par caractère, et c'est ce
          // qui permet de repérer une faute de frappe.
          .font(.callout.monospaced())
          .lineLimit(1)
          .autocorrectionDisabled()
          .layoutPriority(1)
          #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
          #endif

          HStack(spacing: 12) {
            Button("Se connecter") {
              Task { await modele.connecter() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(modele.enChargement || modele.adresse.isEmpty)

            Button("Tester l'adresse") {
              Task { await modele.testerAdresse() }
            }
            .disabled(modele.enChargement || modele.adresse.isEmpty)

            if modele.enChargement { ProgressView().controlSize(.small) }
          }

          // Le résultat du test, NOMMÉ : « rien ne s'est passé » ne doit jamais
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
              .fixedSize(horizontal: false, vertical: true)
          }
        } header: {
          Text("Adresse du Mac")
        } footer: {
          Text(
            "Le nom MagicDNS du Mac, publié par `tailscale serve` — par exemple mon-mac.mon-tailnet.ts.net. Sans protocole, `http://` est supposé."
          )
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .navigationTitle("Adresse")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Terminé") { fermer() }
        }
      }
    }
    #if os(macOS)
      // Une adresse de tailnet fait une quarantaine de caractères : la feuille
      // doit être assez large pour l'afficher entière (même mesure que les
      // réglages, même correction).
      .frame(minWidth: 520, idealWidth: 580, minHeight: 280)
    #endif
  }
}
