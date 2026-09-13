import Foundation

/// LES TRACES DE L'APPLICATION — éteintes par défaut, allumées à la demande.
///
/// POURQUOI ELLES EXISTENT. Quatre mesures de cette session n'auraient pas été
/// possibles sans elles : le verdict de la sonde (16 à 183 ms), la durée d'une
/// connexion (4,3 s à chaud, **23,7 s** sur un harness fraîchement redémarré), le
/// nombre de serveurs reçus de l'hôte, et l'oscillation d'adresse entre deux
/// machines — celle qui a révélé que « choisi » et « visé » étaient cinq champs
/// écrits par dix-sept endroits. Une application lancée depuis le Dock n'a pas de
/// terminal : ces lignes sont la seule fenêtre sur ce qu'elle fait.
///
/// POURQUOI ELLES SONT ÉTEINTES. Personne ne les lit au quotidien, et une sortie
/// qui parle toujours finit par être ignorée — y compris le jour où elle dit
/// quelque chose d'important. Elles ne s'allument donc que si on le demande :
///
///     DSH_REMOTE_TRACE=1 "/Applications/DSH Remote.app/Contents/MacOS/DSHRemoteMac"
///
/// L'outil en ligne de commande (`--sonder`) n'utilise PAS ce filtre : chez lui,
/// afficher EST le métier.
public enum Trace {
  /// L'application a-t-elle été lancée avec `DSH_REMOTE_TRACE=1` ?
  public static let active = ProcessInfo.processInfo.environment["DSH_REMOTE_TRACE"] == "1"

  /// Écrit le message — et ne le CONSTRUIT que si les traces sont allumées.
  ///
  /// L'`@autoclosure` n'est pas une coquetterie : les messages interpolent des
  /// compteurs et des durées à chaque sonde, toutes les quinze secondes. Sans
  /// elle, on paierait la construction de chaînes que personne ne lirait.
  public static func siActive(_ message: @autoclosure () -> String) {
    guard active else { return }
    print(message())
  }
}
