import Foundation

/// CE QUE FAIT UN APPUI SUR UNE MACHINE — et pourquoi ce n'est pas « les deux ».
///
/// POURQUOI CETTE RÈGLE EXISTE, ET CE QU'ELLE CORRIGE. La vignette faisait
/// « OUVRIR **ET** CONNECTER » en un seul geste — c'était même écrit comme une
/// correction : « Toucher une machine, c'est vouloir s'y connecter ; la page, elle,
/// est ce qui l'EXPLIQUE quand ça ne marche pas. » Le raisonnement est bon, mais il
/// manquait une conséquence : sur iPhone, ce geste EMPILE la page de la machine —
/// l'utilisateur qui voulait seulement PASSER sur un autre serveur pour voir ses
/// sessions se retrouvait sur une fiche, et devait revenir en arrière.
///
/// La règle demandée sépare donc les deux temps :
///
///   1. **un appui sur une machine qui n'est pas la cible** la SÉLECTIONNE : la
///      cible change, l'application s'y reconnecte, et **ses** sessions et **ses**
///      espaces de travail se rechargent. On reste sur la liste — c'est ce qu'on
///      est venu voir ;
///   2. **un appui sur la machine DÉJÀ sélectionnée** ouvre sa page de détail :
///      son état, ses actions, ses remèdes.
///
/// C'EST UNE RÈGLE, PAS UN `if` DANS UNE VUE : elle décide d'un comportement
/// observable, et elle se vérifie sans interface.
public enum GesteSurServeur: Equatable, Sendable {
  /// La machine n'est pas la cible : on la sélectionne (et on se reconnecte).
  case selectionner
  /// C'est déjà la cible : on ouvre sa page de détail.
  case ouvrirLaPage

  /// LA DÉCISION, EN UNE FONCTION PURE.
  ///
  /// - Parameters:
  ///   - serveur: la machine touchée.
  ///   - choisi: la machine actuellement visée, s'il y en a une.
  public static func pour(_ serveur: ServeurMac, choisi: ServeurMac?) -> GesteSurServeur {
    // LA COMPARAISON PORTE SUR L'IDENTITÉ, PAS SUR LA VALEUR ENTIÈRE : `choisi`
    // vient de la cible et `serveur` de la liste ; deux instances du même hôte
    // peuvent différer par un champ d'affichage (`enLigne`, par exemple, qui
    // change avec la découverte). Comparer les valeurs entières ferait rater la
    // reconnaissance, et un second appui sélectionnerait au lieu d'ouvrir.
    choisi?.id == serveur.id ? .ouvrirLaPage : .selectionner
  }
}
