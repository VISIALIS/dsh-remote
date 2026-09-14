import Foundation

/// LA MACHINE SÉLECTIONNÉE QUAND AUCUNE NE L'EST — une règle, pas un effet de bord.
///
/// LA RÈGLE, DITE PAR LE PROPRIÉTAIRE : « il doit toujours y avoir un serveur
/// sélectionné » — la coche en haut à gauche de la vignette, et sous elle les
/// espaces de travail de CE serveur.
///
/// LE DÉFAUT MESURÉ, ET POURQUOI IL NE POUVAIT PAS SE VOIR AILLEURS. Au lancement
/// sur iPhone, l'application se connecte D'ABORD à l'adresse mémorisée, et la
/// liste des machines n'arrive qu'APRÈS — c'est cet hôte qui la publie. Rien ne
/// rattachait alors la machine jointe à la cible : la liste s'affichait sans
/// aucune coche, et le panneau des espaces restait vide. Sur macOS, l'ordre est
/// inverse (on découvre, puis on se connecte), donc le défaut n'y apparaissait
/// pas — un défaut d'ORDRE se cache toujours dans la plateforme où l'ordre est
/// favorable.
///
/// TROIS TEMPS, ET TROIS RÉPONSES DIFFÉRENTES.
///
///   1. **une machine de la liste PORTE l'adresse courante** : c'est celle-là.
///      Ce n'est pas un choix, c'est un fait — on lui parle déjà ;
///   2. **la liste vient de l'hôte, et elle le DÉSIGNE** (`estLocal`) : c'est
///      lui. Encore un fait, et c'est celui qui manquait : sur iPhone
///      l'application joint l'hôte par `127.0.0.1` (simulateur) ou par une
///      adresse qui n'est pas celle que l'hôte publie pour lui-même, donc aucune
///      correspondance d'adresse n'aboutissait — mesuré sur simulateur :
///      « MacBook Air » et « MacMini » affichés, connecté, les espaces de travail
///      chargés, et AUCUNE coche ;
///   3. **aucune des deux** : au LANCEMENT on prend la première de la liste
///      affichée (c'est la règle demandée : « par défaut, c'est le premier
///      serveur de la liste »), mais PAS après une réponse de l'hôte — là, on
///      parle déjà à quelqu'un, et changer de cible jetterait les sessions et
///      les espaces qui viennent d'être chargés.
public enum SelectionParDefaut {
  /// CE QUI A ÉTÉ RECONNU — parce que la CONSÉQUENCE diffère.
  ///
  /// POURQUOI UN TYPE, ET PAS SEULEMENT UNE MACHINE. Attacher et remplacer ne
  /// coûtent pas la même chose : attacher ajoute un nom à la cible courante,
  /// remplacer change d'adresse et JETTE les sessions et les espaces de travail
  /// de celle qu'on vient de joindre. Mesuré sur simulateur : avec un simple
  /// « remplacer », la coche est apparue et les six sessions ont disparu. Le
  /// premier et le deuxième cas sont des FAITS (« c'est elle qu'on joint ») ;
  /// le troisième est un CHOIX par défaut, et lui seul remplace.
  public enum Reconnaissance: Equatable {
    /// L'adresse courante désigne cette machine.
    case jointe(ServeurMac)
    /// La liste vient de l'hôte, et elle le désigne lui-même.
    case hote(ServeurMac)
    /// Au lancement, faute de mieux : la première de la liste affichée.
    case premiere(ServeurMac)

    public var machine: ServeurMac {
      switch self {
      case let .jointe(machine), let .hote(machine), let .premiere(machine): return machine
      }
    }
  }

  /// La machine de la liste qui porte l'adresse courante, s'il y en a une.
  ///
  /// La comparaison passe par `IdentiteHote.cle` : deux écritures de la même
  /// adresse (`mac.exemple.ts.net` et `http://mac.exemple.ts.net`) désignent la
  /// même machine, et c'est cette fonction qui le sait déjà pour les jetons.
  public static func machineJointe(
    parmi serveursAffiches: [ServeurMac], adresse: String
  ) -> ServeurMac? {
    let cle = IdentiteHote.cle(adresse)
    guard !cle.isEmpty else { return nil }
    return serveursAffiches.first { IdentiteHote.cle($0.adresse) == cle }
  }

  /// La machine à sélectionner, ou `nil` s'il n'y a rien à sélectionner.
  ///
  /// - Parameter listeVientDeLHote: `true` quand la liste a été publiée par
  ///   l'hôte qu'on interroge. Lui seul marque SA machine (`estLocal`) ; la
  ///   découverte locale, elle, marque CETTE machine — qui n'est pas forcément
  ///   celle à qui l'on parle. Le drapeau n'est donc pas une commodité : il
  ///   décide si le marqueur est un fait ou un piège.
  /// - Parameter remplacerFauteDeMieux: `true` au LANCEMENT seulement. Après une
  ///   réponse de l'hôte, on préfère ne rien changer plutôt que de changer de
  ///   cible : une cible remplacée vide les sessions et les espaces de travail
  ///   de celle qu'on vient de joindre.
  public static func aSelectionner(
    parmi serveursAffiches: [ServeurMac], adresse: String, listeVientDeLHote: Bool,
    remplacerFauteDeMieux: Bool
  ) -> Reconnaissance? {
    if let jointe = machineJointe(parmi: serveursAffiches, adresse: adresse) {
      return .jointe(jointe)
    }
    if listeVientDeLHote, let hote = serveursAffiches.first(where: \.estLocal) {
      return .hote(hote)
    }
    guard remplacerFauteDeMieux, let premiere = serveursAffiches.first else { return nil }
    return .premiere(premiere)
  }
}
