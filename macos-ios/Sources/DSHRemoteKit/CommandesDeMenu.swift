#if os(macOS)
  import SwiftUI

  /// LE CANAL DES COMMANDES DE MENU VERS LA FENÊTRE ACTIVE.
  ///
  /// POURQUOI IL EXISTE. Un ⌘F doit donner le focus au champ de recherche de la
  /// fenêtre au premier plan — et une commande SwiftUI ne voit pas les vues : elle
  /// ne voit que des `FocusedValue`. La vue publie donc ici l'action qu'elle sait
  /// faire, et la commande l'appelle.
  ///
  /// POURQUOI UNE CLÔTURE, ET NON UN DRAPEAU DANS LE MODÈLE. Le focus d'un champ
  /// vit dans un `@FocusState`, que seule la vue qui le possède peut écrire.
  /// Publier « focus demandé » obligerait à un compteur dans le modèle, à une
  /// seconde mécanique d'observation, et à décider quand remettre le compteur à
  /// zéro — trois occasions de divergence pour un raccourci clavier. Publier
  /// l'action dit exactement ce dont la commande a besoin, et rien de plus.
  ///
  /// POURQUOI macOS SEULEMENT. Sur iOS, il n'y a pas de menu : les raccourcis
  /// clavier n'existent que pour un clavier externe, où le champ se touche
  /// directement.
  struct FocusRecherche: FocusedValueKey {
    public typealias Value = () -> Void
  }

  extension FocusedValues {
    /// L'action publiée par la barre de recherche de la fenêtre active.
    ///
    /// PUBLIQUE, ET C'EST NÉCESSAIRE : la commande de menu vit dans le module de
    /// l'application macOS, pas dans cette bibliothèque.
    public var focusRecherche: (() -> Void)? {
      get { self[FocusRecherche.self] }
      set { self[FocusRecherche.self] = newValue }
    }
  }
#endif
