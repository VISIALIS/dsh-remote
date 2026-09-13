import SwiftUI

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Une ligne de commande à recopier **telle quelle**, avec son bouton.
///
/// POURQUOI CE COMPOSANT. Le message d'aide affichait ses commandes en texte
/// monospace, noyées dans un paragraphe : il fallait les sélectionner à la main —
/// sur un téléphone, avec un clavier qui n'aide pas, et une sélection qui attrape
/// volontiers la ligne voisine. Or ces commandes ne sont pas destinées à être
/// LUES ici : elles sont destinées à être TAPÉES sur un autre Mac. Une commande
/// qui doit voyager se copie.
///
/// Le bouton confirme brièvement son effet : sans retour visuel, on ne sait pas
/// si l'appui a été pris en compte, et on appuie deux fois.
///
/// Ce qui est copié est EXACTEMENT la chaîne affichée — pas de retour à la ligne
/// ajouté, pas d'indentation : une commande collée dans un terminal s'exécute.
struct LigneCommande: View {
  let commande: String

  @State private var copie = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(commande)
        .font(.caption.monospaced())
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 4)
      Button {
        copier()
      } label: {
        Image(systemName: copie ? "checkmark" : "doc.on.doc")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .help(copie ? "Commande copiée" : "Copier la commande")
      .accessibilityLabel(copie ? "Commande copiée" : "Copier la commande \(commande)")
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
  }

  private func copier() {
    #if canImport(UIKit)
      UIPasteboard.general.string = commande
    #elseif canImport(AppKit)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(commande, forType: .string)
    #endif
    copie = true
    Task {
      try? await Task.sleep(nanoseconds: 1_800_000_000)
      copie = false
    }
  }
}

extension View {
  /// Masque le séparateur de ligne **sur macOS seulement**.
  ///
  /// POURQUOI. Le propriétaire a demandé si ces traits étaient utiles sur le Mac :
  /// ils ne le sont pas. Une colonne de navigation macOS n'en dessine aucun — la
  /// liste latérale du système n'a pas de séparateurs — et ici ils découpent des
  /// lignes qui appartiennent au MÊME objet : un espace et ses sessions, une
  /// carte et sa légende, une explication et sa commande.
  ///
  /// iOS les garde : dans une liste encartée, ils séparent des réglages
  /// distincts, et leur absence donnerait une bouillie indistincte.
  ///
  /// L'API est appliquée à CHAQUE ligne, et non au `List` : `listRowSeparator`
  /// est un modificateur de ligne, et le poser sur un conteneur ne le propage
  /// pas — il serait alors sans effet, ce qui est pire qu'un séparateur.
  @ViewBuilder
  func sansSeparateurMac() -> some View {
    #if os(macOS)
      self.listRowSeparator(.hidden)
    #else
      self
    #endif
  }
}
