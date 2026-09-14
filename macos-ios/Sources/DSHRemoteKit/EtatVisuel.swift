import SwiftUI

/// L'ÉTAT D'UNE CHOSE, DIT DE LA MÊME FAÇON PARTOUT — la table qui manquait.
///
/// POURQUOI CE TYPE EXISTE. L'application choisissait ses couleurs d'état à
/// chaque endroit : `.orange` ici, `.green` là, `.red` ailleurs — et une
/// deuxième petite table pour l'écriture, une troisième pour les étapes. C'est
/// exactement ce qu'un commentaire de `EtatMachine` disait vouloir éviter
/// (« trois tables de couleurs auraient fini par diverger ») : il y en avait
/// déjà deux, et des littéraux un peu partout.

/// LA PARITÉ AVEC L'INTERFACE WEB, ET POURQUOI ELLE PASSE PAR ICI. L'interface
/// web de DSH nomme ses états par FAMILLE (`--dsw-alias-state-warn-primary`,
/// `-label`, `-tertiary`, et de même pour `success`, `error`, `business`) : une
/// couleur ne dit pas seulement « c'est vert », elle dit **de quel genre de
/// chose il s'agit**. L'application ne peut pas consommer ces jetons — c'est une
/// application native, et les couleurs du système sont ce qui s'adapte
/// automatiquement au mode sombre, au contraste augmenté et aux réglages
/// d'accessibilité. Ce qu'elle PEUT partager, c'est le **vocabulaire** : les
/// mêmes cinq états, les mêmes mots, les mêmes symboles. C'est ce que fait ce
/// type, et c'est ce qui manquait pour que les deux surfaces racontent la même
/// histoire avec deux langues différentes.
///
/// LA RÈGLE QUI VA AVEC, ET ELLE VIENT DE L'AUDIT (A5, `AUDIT-UX-UI.md`) :
/// **jamais la couleur seule.** Chaque état porte donc un MOT, et un symbole
/// distinct. Un site qui a une formulation plus précise que le mot générique la
/// garde — c'est le mot de l'état qui est fourni ici, pas une obligation de
/// l'afficher quand le texte autour dit déjà mieux.
public enum EtatVisuel: Equatable, Sendable, CaseIterable {
  /// Ça marche. Vert, et il n'y a rien à faire.
  case pret
  /// Ça peut marcher, mais quelque chose manque ou n'est pas certain.
  case attention
  /// Ça ne marche pas, et l'utilisateur doit agir.
  case erreur
  /// On ne sait pas encore — ou c'est en cours. Gris, parce qu'un état qu'on
  /// ignore ne doit pas crier plus fort qu'un état qu'on constate.
  case attente
  /// Une information neutre, sans jugement : « ceci est la machine courante ».
  case information

  /// LA COULEUR — décidée ICI, une fois. Elle vient des styles du SYSTÈME
  /// (`.green`, `.orange`, `.red`, `.secondary`, `Color.accentColor`), donc elle
  /// s'adapte au mode sombre et au contraste augmenté sans une ligne de plus.
  public var couleur: Color {
    switch self {
    case .pret: return .green
    case .attention: return .orange
    case .erreur: return .red
    case .attente: return .secondary
    case .information: return .accentColor
    }
  }

  /// LE SYMBOLE PAR DÉFAUT de l'état — distinct d'un état à l'autre, pour que la
  /// forme dise la même chose que la couleur (règle A5).
  ///
  /// Un site peut employer un symbole PLUS PRÉCIS que celui-ci (`moon.zzz.fill`
  /// pour une machine éteinte, plutôt que le triangle générique) : il dit alors
  /// *ce qui* ne va pas, en plus de *à quel point*. Ce qui n'est pas permis, c'est
  /// de choisir une couleur d'état ailleurs qu'ici.
  public var symbole: String {
    switch self {
    case .pret: return "checkmark.circle.fill"
    case .attention: return "exclamationmark.triangle.fill"
    case .erreur: return "xmark.circle.fill"
    case .attente: return "clock"
    case .information: return "info.circle"
    }
  }

  /// LE MOT DE L'ÉTAT — celui qu'on peut afficher quand le texte autour ne dit
  /// pas déjà l'état. Jamais la couleur seule : c'est la règle A5, et elle est
  /// ici plutôt que répétée dans chaque vue.
  public var mot: String {
    switch self {
    case .pret: return L("prêt")
    case .attention: return L("à vérifier")
    case .erreur: return L("erreur")
    case .attente: return L("en attente")
    case .information: return L("information")
    }
  }
}
