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
  /// AUCUN PORTEUR N'EST PRÉSENTÉ, ET C'EST UNE RÈGLE DE SÉCURITÉ. La sonde
  /// interroge les machines d'un tailnet qui NE SONT PAS la cible : leur envoyer
  /// le jeton de la cible ferait voyager un secret vers des hôtes qui n'en ont
  /// aucun besoin, et chacun d'eux pourrait le rejouer. Or ce jeton n'apporte rien
  /// ici : la question est « y a-t-il un DSH en face ? », et un `401` y répond
  /// aussi bien qu'un `200` — le service a répondu, seul le porteur manquait.
  /// C'est la même règle que celle du modèle, où chaque hôte a SON jeton.
  ///
  /// Les sondes partent ENSEMBLE : une machine éteinte ne doit pas retarder les
  /// autres. Le verdict est rendu même si la tâche est annulée en route — c'est
  /// au modèle de décider s'il a encore le droit de le publier, car lui seul sait
  /// si la cible a changé depuis.
  public func interroger(_ candidats: [ServeurMac]) async -> Verdict {
    let fabrique = self.fabrique
    return await withTaskGroup(of: (String, Bool, CauseSansDsh?).self) { groupe in
      for serveur in candidats {
        groupe.addTask {
          await Sonde.sonderUnCandidat(serveur, fabrique: fabrique)
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

  /// Sonde UN candidat, borné à `Sonde.delai` — QUELLE QUE SOIT LA CONFIGURATION
  /// RÉSEAU.
  ///
  /// POURQUOI CETTE COURSE EXISTE, ET CE QU'ELLE CORRIGE. `ConfigurationReseau
  /// .pourRequetes` pose `waitsForConnectivity = true` et un PLANCHER de 120 s
  /// sur `timeoutIntervalForResource`, pensés pour `Connexion` — une adresse qui
  /// n'a provisoirement AUCUNE route (Wi-Fi qui bascule, radio qui se réveille)
  /// mérite d'attendre. `Sonde.delai` (2,5 s) et le délai de requête
  /// (`timeoutIntervalForRequest`) ne bornent PAS cette attente : mesuré, une
  /// machine sortie du tailnet (dans `tailscale status`, mais encore comptée
  /// « en ligne » par la découverte) a fait tenir `interroger` 120 secondes,
  /// pour DEUX candidats dont l'un répondait en 12 ms — le verdict du second
  /// retenait le premier en otage, le temps que `URLSession` cesse d'espérer une
  /// connectivité qui ne revient pas.
  ///
  /// La course locale rend donc vraie la promesse du commentaire ci-dessus
  /// (« borné à 2,5 s ») : passé ce délai, le candidat compte comme muet, et sa
  /// requête réseau est annulée avec le reste de la course.
  private static func sonderUnCandidat(
    _ serveur: ServeurMac, fabrique: @escaping Connexion.Fabrique
  ) async -> (String, Bool, CauseSansDsh?) {
    await withTaskGroup(of: (String, Bool, CauseSansDsh?).self) { course in
      course.addTask {
        // Le porteur VIDE est ce qui fait que `RemoteClient` ne pose aucun
        // en-tête `Authorization` (voir sa méthode `requete`).
        guard let client = try? fabrique(serveur.adresse, "", Sonde.delai) else {
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
      course.addTask {
        try? await Task.sleep(for: .seconds(Sonde.delai))
        // Aucune cause : le silence n'en est pas une, il dit seulement qu'on a
        // cessé d'attendre.
        return (serveur.id, false, nil)
      }
      // Le PREMIER des deux gagne — la vraie réponse, ou l'horloge — et l'autre
      // est annulé : une requête réseau en vol se voit notifiée de l'annulation
      // (`URLSession.data(for:)` l'observe), elle ne continue pas en silence.
      let premier = await course.next()!
      course.cancelAll()
      return premier
    }
  }
}
