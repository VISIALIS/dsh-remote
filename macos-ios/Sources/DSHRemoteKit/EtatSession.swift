import SwiftUI

/// État visuel d'une session dans la liste.
///
/// POURQUOI UN TYPE PLUTÔT QU'UN BOOLÉEN. L'interface web distingue plusieurs
/// situations — un tour en cours, une décision attendue, une fin non vue, un état
/// inconnu — et un simple « vivante » les confondait toutes. Le serveur transporte
/// maintenant ce qu'il faut pour les distinguer, et ce type en fait un affichage.
///
/// CE QUI NE S'AFFICHE PAS COMPTE AUSSI. Une session au repos n'a PAS d'indicateur
/// (`.rien`) : c'est le cas le plus fréquent, et lui donner une pastille — un point
/// bleu, dans une version précédente — revenait à décorer la liste d'une
/// information qui n'appelle aucune action. L'interface web masque elle aussi sa
/// pastille dans ce cas.
public enum EtatSession: Sendable, Equatable {
  /// Rien à signaler : la session est chargée et au repos.
  case rien
  /// Un tour s'exécute : le modèle travaille.
  case enCours
  /// Le harness attend une DÉCISION de l'utilisateur (question d'un tool ou
  /// autorisation). Une session dans cet état ne repartira pas toute seule.
  ///
  /// C'est l'information la plus actionnable de la liste, et elle PRIME sur
  /// « en cours » : l'agent travaille, mais il est bloqué sur vous.
  case attendReponse
  /// Un tour vient de se TERMINER et l'utilisateur ne l'a pas encore vu.
  ///
  /// C'est le rappel de fin de l'interface web, et il ne dit PAS la même chose
  /// que l'inactivité : une session au repos depuis toujours n'affiche rien, une
  /// session qui vient de finir est verte. La différence est celle qui compte
  /// quand on a lancé un travail et qu'on attend son résultat.
  case terminee
  /// Session présente sur disque mais absente du processus : état INCONNU.
  ///
  /// CE CAS NE DOIT PAS RESSEMBLER À UN AUTRE. Il était affiché comme un point
  /// vert, c'est-à-dire comme une session TERMINÉE : l'interface affirmait donc
  /// quelque chose qu'elle ne savait pas. Un état inconnu se montre comme
  /// inconnu — anneau vide — et jamais comme une conclusion.
  case inconnue

  /// - Parameters:
  ///   - statut: `en_cours`, `inactif`, ou `nil` quand la session n'est pas
  ///     ouverte dans le processus du harness.
  ///   - vivante: le harness connaît-il encore cette session ?
  ///   - rappelDeFin: une fin de tour non vue a-t-elle été détectée ?
  ///     Voir `RappelsDeFin` pour la règle, qui est une transition et non un champ.
  ///   - attendReponse: le harness attend-il une décision de l'utilisateur ?
  public init(
    statut: String?, vivante: Bool?, rappelDeFin: Bool = false, attendReponse: Bool = false
  ) {
    // L'ordre est délibéré, et il est lisible : ce qui demande une ACTION passe
    // avant ce qui décrit une activité. Une question en attente prime sur le
    // travail en cours (l'agent est bloqué sur vous), qui prime sur un rappel de
    // fin déjà consommable, qui prime sur le silence.
    if attendReponse {
      self = .attendReponse
    } else if statut == "en_cours" {
      self = .enCours
    } else if rappelDeFin {
      self = .terminee
    } else if statut == "inactif" {
      self = .rien
    } else {
      self = .inconnue
    }
  }

  /// L'ÉTAT D'UNE SESSION LISTÉE — la règle unique, en un seul endroit.
  ///
  /// POURQUOI ELLE EXISTE. La liste, le tri d'urgence et le compteur par espace
  /// répondent à la même question : « que demande cette session ? ». Trois
  /// calculs séparés auraient fini par diverger — une session comptée « en
  /// attente » dans un espace et pas dans la section qui la met en avant.
  public static func de(_ session: SessionListee, rappelDeFin: Bool) -> EtatSession {
    EtatSession(
      statut: session.statut, vivante: session.vivante, rappelDeFin: rappelDeFin,
      attendReponse: session.attendReponse == true)
  }

  /// Vrai si l'indicateur doit s'animer.
  public var anime: Bool { self == .enCours }

  /// L'ÉTAT, DIT EN TOUTES LETTRES — pour VoiceOver, et pour tout ce qui doit
  /// nommer un état sans le montrer.
  ///
  /// POURQUOI CE N'EST PAS DÉCORATIF. La liste portait son information la plus
  /// actionnable dans une FORME et une COULEUR : quatre carrés orange qui
  /// tournent, un point orange plein, un point vert, un anneau gris. Un lecteur
  /// d'écran annonçait donc « 27 évts, 1,2 Mo, il y a 3 minutes » sans jamais
  /// dire laquelle des sessions l'attend — c'est-à-dire sans dire la seule chose
  /// qui appelle une action de sa part.
  ///
  /// Le vocabulaire est celui des commentaires du type, et pas un synonyme
  /// inventé ici : « attend votre réponse » dit à qui l'état s'adresse.
  public var libelle: String {
    switch self {
    case .rien: return L("au repos")
    case .enCours: return L("tour en cours")
    case .attendReponse: return L("attend votre réponse")
    case .terminee: return L("terminée, pas encore lue")
    case .inconnue: return L("état inconnu")
    }
  }
}
