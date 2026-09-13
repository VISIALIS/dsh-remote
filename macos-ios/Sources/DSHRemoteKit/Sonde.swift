import Foundation

/// LA SONDE : qui, parmi ces machines, sert DSH — et POURQUOI les autres non.
///
/// POURQUOI ELLE VIT HORS DU MODÈLE. Le modèle garde l'ÉTAT (« on ne sait pas »,
/// « on interroge », « on sait ») et les règles qui l'entourent : ne pas sonder
/// une machine hors ligne, ne pas republier un verdict annulé. Cette pièce-ci ne
/// fait que POSER LA QUESTION et rassembler les réponses — et comme sa fabrique
/// de clients s'injecte, on l'éprouve sans réseau.
///
/// POURQUOI ELLE EXISTE, EN UNE PHRASE : la découverte dit quelles machines sont
/// EN LIGNE, pas lesquelles servent DSH. Le propriétaire a choisi un Mac où DSH
/// tournait — et a reçu « rien n'écoute sur cet hôte et ce port », parce que
/// `tailscale serve` n'y était pas actif. L'application proposait une machine
/// sans savoir si elle pouvait répondre.
public struct Sonde: Sendable {

  /// Délai d'une sonde, court À DESSEIN.
  ///
  /// Un Mac qui publie DSH répond en quelques millisecondes sur le tailnet, et un
  /// Mac muet ne mérite pas qu'on l'attende : c'est le verdict le plus rapide de
  /// l'application (mesuré : 16 à 183 ms, borné à 2,5 s par machine).
  public static let delai: TimeInterval = 2.5

  /// Ce qu'une sonde a appris : qui sert DSH, et la cause pour les autres.
  ///
  /// POURQUOI LES CAUSES SONT GARDÉES. Un ensemble de noms suffisait à colorer
  /// une vignette, pas à REMÉDIER : dire « le plugin n'est pas installé » exige
  /// de savoir si la machine a répondu autre chose (`404`) ou rien du tout
  /// (`-1004`). Sans cela, la page d'une machine non visée n'avait aucun remède —
  /// et celle d'une machine visée pouvait en donner un faux.
  public struct Verdict: Equatable, Sendable {
    public var serventDsh: Set<String> = []
    /// La cause, par identifiant de machine — pour celles qui ne servent pas DSH.
    public var causes: [String: CauseSansDsh] = [:]

    public init(serventDsh: Set<String> = [], causes: [String: CauseSansDsh] = [:]) {
      self.serventDsh = serventDsh
      self.causes = causes
    }
  }

  private let fabrique: Connexion.Fabrique

  public init(fabrique: @escaping Connexion.Fabrique = Connexion.fabriqueParDefaut) {
    self.fabrique = fabrique
  }

  /// Interroge chaque machine, EN PARALLÈLE, et rassemble le verdict.
  ///
  /// Les sondes partent ENSEMBLE : une machine éteinte ne doit pas retarder les
  /// autres. Le verdict est rendu même si la tâche est annulée en route — c'est
  /// au modèle de décider s'il a encore le droit de le publier, car lui seul sait
  /// si la cible a changé depuis.
  public func interroger(_ candidats: [ServeurMac], jeton: String) async -> Verdict {
    let fabrique = self.fabrique
    return await withTaskGroup(of: (String, Bool, CauseSansDsh?).self) { groupe in
      for serveur in candidats {
        groupe.addTask {
          guard let client = try? fabrique(serveur.adresse, jeton, Sonde.delai) else {
            return (serveur.id, false, nil)
          }
          // `verifierSante` ne rend aucune donnée de session : c'est la poignée
          // de main. Deux réponses disent que DSH est LÀ : un `200`, et un `401`
          // — car un jeton refusé PROUVE que le service a répondu. Toute autre
          // erreur (délai, connexion refusée, DNS) veut dire « rien au bout ».
          do {
            _ = try await client.verifierSante()
            return (serveur.id, true, nil)
          } catch ErreurRemote.jetonRefuse {
            return (serveur.id, true, nil)
          } catch {
            // ON RETIENT LA CAUSE, pas seulement l'échec : c'est elle qui permet
            // à la page de cette machine de dire quoi faire.
            return (serveur.id, false, (error as? ErreurRemote)?.causeSansDsh)
          }
        }
      }
      var verdict = Verdict()
      for await (identifiant, repond, cause) in groupe {
        if repond {
          verdict.serventDsh.insert(identifiant)
        } else if let cause {
          verdict.causes[identifiant] = cause
        }
      }
      return verdict
    }
  }
}
