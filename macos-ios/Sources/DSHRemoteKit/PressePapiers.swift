import Foundation

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// ÉCRIRE DANS LE PRESSE-PAPIERS, SANS COMPOSANT D'INTERFACE.
///
/// POURQUOI CE FICHIER EXISTE. Copier une valeur était jusqu'ici le fait d'un
/// seul composant, `LigneCommande`, qui portait à la fois le dessin, l'acquittement
/// visuel et l'écriture système. Les gestes de liste ont maintenant besoin de la
/// même écriture sans aucun dessin — « Copier le titre », « Copier l'adresse »
/// dans un menu contextuel —, et deux copies de ce code auraient fini par
/// diverger sur ce qui compte : le type déposé, et le fait que le presse-papiers
/// est bien vidé avant écriture.
///
/// CE QU'ELLE NE FAIT PAS. Aucun retour visuel, aucune confirmation : c'est à
/// l'appelant de dire que la copie a eu lieu. Un menu contextuel se referme en
/// emportant le message, c'est pourquoi les entrées de menu portent leur propre
/// libellé (« Copier le titre ») plutôt qu'un état.
public enum PressePapiers {
  /// Dépose `texte` dans le presse-papiers de la plateforme.
  ///
  /// `clearContents()` AVANT L'ÉCRITURE n'est pas une précaution de style : sur
  /// AppKit, écrire sans vider laisse cohabiter l'ancien et le nouveau contenus
  /// sous des types différents, et un collage peut alors rendre la valeur
  /// précédente. Constaté en collant une adresse après une commande.
  public static func ecrire(_ texte: String) {
    #if canImport(UIKit)
      UIPasteboard.general.string = texte
    #elseif canImport(AppKit)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(texte, forType: .string)
    #endif
  }
}
