import Foundation

/// LE LIBELLÉ D'UNE VIGNETTE DE MACHINE — un mot, ou deux quand un seul ne suffit pas.
///
/// POURQUOI CE N'EST PAS « LE PREMIER MOT », ET POURQUOI ÇA SE CALCULE PAR LISTE.
/// Les noms que Tailscale rapporte sont construits sur le modèle matériel
/// (« MacBook Air de Camille », « MacStudio Atelier »), et une vignette de 68
/// points n'en affiche qu'un mot : le premier est donc le bon par défaut. Mais
/// deux machines peuvent le PARTAGER — les données d'essai de ce dépôt en
/// contiennent deux, « Portable Un » et « Portable Deux », affichées toutes deux
/// « Portable » —, et l'appui sur une vignette CHANGE la connexion : deux
/// vignettes identiques font choisir à pile ou face.
///
/// Un libellé ne peut donc pas se décider vignette par vignette : c'est la
/// COMPARAISON entre machines qui dit s'il distingue, et elle se fait sur la liste
/// entière. D'où une fonction qui prend la liste et rend un libellé par machine,
/// plutôt qu'une propriété d'une machine seule.
///
/// CE QU'ELLE NE FAIT PAS. Elle ne raccourcit pas plus que demandé : un nom déjà
/// unique garde UN mot, même long, parce que c'est la forme sous laquelle on
/// reconnaît une machine. Elle ne traduit rien, et VoiceOver continue de lire le
/// nom complet, qui n'a pas cette contrainte de place.
public enum NomsCourts {
  /// Le libellé de chaque machine, par identifiant (son nom DNS).
  ///
  /// Règle : le premier mot, sauf s'il est partagé — auquel cas on allonge d'un
  /// mot, jusqu'à `motsMax`. Au-delà, deux machines réellement homonymes gardent
  /// le même libellé : c'est la vérité du tailnet, et l'inventer serait pire.
  public static func libelles(pour serveurs: [ServeurMac], motsMax: Int = 2) -> [String: String] {
    var libelles: [String: String] = [:]
    let plafond = max(1, motsMax)

    // Chaque tour fixe les machines dont le raccourci de `mots` mots est UNIQUE,
    // et laisse les autres au tour suivant, plus long d'un mot.
    for mots in 1...plafond {
      let restants = serveurs.filter { libelles[$0.id] == nil }
      guard !restants.isEmpty else { break }
      for (raccourci, membres) in Dictionary(grouping: restants, by: { raccourci($0.nom, mots: mots) }) {
        if membres.count == 1 || mots == plafond {
          for membre in membres { libelles[membre.id] = raccourci }
        }
      }
    }
    return libelles
  }

  /// Les `mots` premiers mots d'un nom — le nom entier s'il est plus court.
  ///
  /// Les espaces multiples et les espaces de bord sont absorbés par `split`, qui
  /// ne rend que les morceaux non vides : un nom saisi à la main dans Tailscale
  /// peut en contenir. C'est LA règle de découpage du paquet : `ServeurMac.premierMot`
  /// l'emploie aussi, pour qu'il n'y en ait qu'une.
  public static func raccourci(_ nom: String, mots: Int) -> String {
    let morceaux = nom.split(separator: " ")
    guard morceaux.count > mots else { return nom }
    return morceaux.prefix(mots).joined(separator: " ")
  }
}
