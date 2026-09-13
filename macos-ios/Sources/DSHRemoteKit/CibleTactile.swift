import SwiftUI

extension View {
  /// ÉLARGIT UNE CIBLE TACTILE, SANS CHANGER SON DESSIN.
  ///
  /// POURQUOI. Les directives Apple donnent 44 × 44 points comme cible par
  /// défaut au doigt. Les boutons d'icône de cette application sont dessinés au
  /// plus juste — `.font(.caption)` pour copier une commande, `.title2` pour
  /// envoyer un message, une image de 12 points pour effacer une recherche —, si
  /// bien que la surface réellement cliquable faisait une douzaine de points de
  /// côté. Or ce sont les gestes les plus fréquents de l'application, et ceux
  /// qu'on rate le plus cher : recopier une commande, coller un jeton,
  /// interrompre un tour.
  ///
  /// POURQUOI UN CADRE ET UN `contentShape`. Le cadre seul ne change RIEN à la
  /// zone qui répond : sans `contentShape`, seuls les pixels dessinés sont
  /// cliquables, et le cadre ne serait qu'un trou dans la mise en page. Les deux
  /// vont donc ensemble.
  ///
  /// SUR macOS, LA CIBLE RESTE CELLE DU POINTEUR : agrandir un bouton de barre y
  /// décalerait les lignes sans rien apporter, la souris n'ayant pas ce
  /// problème. Seul `contentShape` y est posé — il rend cliquable la surface
  /// déjà occupée, ce qui est un gain sans coût.
  @ViewBuilder
  func cibleTactile(_ cote: CGFloat = 44) -> some View {
    #if os(iOS)
      self.frame(minWidth: cote, minHeight: cote).contentShape(Rectangle())
    #else
      self.contentShape(Rectangle())
    #endif
  }
}
