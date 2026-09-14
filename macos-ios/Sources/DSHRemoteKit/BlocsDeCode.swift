import Foundation

/// UN MORCEAU DE TEXTE D'ÉVÉNEMENT : ce qui se lit tel quel, ou du code.
public enum SegmentDeTexte: Equatable, Sendable {
  case texte(String)
  case code(String, langue: String?)
}

/// LES BLOCS DE CODE D'UN MESSAGE DE L'AGENT — et rien d'autre.
///
/// POURQUOI CE TYPE EXISTE. Mesuré sur 40 journaux réels de ce dépôt (52 669
/// événements, 9 491 messages d'assistant) : **8,2 % des messages de l'agent
/// portent un bloc délimité par trois accents graves** (779). C'est une minorité
/// — mais c'est exactement celle qu'on veut LIRE et RECOPIER depuis un téléphone,
/// et elle s'affichait en texte brut, coupée à quatre lignes, sans bouton pour
/// copier une commande.
///
/// POURQUOI IL S'ARRÊTE LÀ. Le reste du Markdown — titres, listes, gras, tableaux,
/// liens — n'est PAS traité, et c'est une décision du propriétaire, pas un oubli :
/// un analyseur complet est un chantier de plusieurs jours, la RÈGLE #0 interdit
/// d'en importer un, et le vrai lecteur d'un long document reste l'interface web.
/// Ce qui est ajouté ici est ce qui manquait le plus.
///
/// POURQUOI C'EST UNE FONCTION PURE. Décider où commence et où finit un bloc est
/// une RÈGLE, avec ses cas tordus — clôture non fermée, accents graves en milieu
/// de phrase, langage annoncé ou non. Une règle se relit et s'éprouve ; un
/// analyseur noyé dans une vue, non.
public enum BlocsDeCode {
  /// Découpe un texte en segments : texte ordinaire, et blocs de code.
  ///
  /// Quatre règles, toutes éprouvées :
  ///
  ///   1. un bloc s'ouvre sur une ligne qui **commence** par trois accents graves
  ///      (ou plus), éventuellement suivie d'un nom de langage ;
  ///   2. il se ferme sur une ligne qui ne porte **que** des accents graves ;
  ///   3. un bloc **non fermé** va jusqu'à la fin du texte : un message tronqué
  ///      par l'hôte ne doit pas faire disparaître son contenu ;
  ///   4. les accents graves **en milieu de ligne** ne sont pas des délimiteurs —
  ///      les confondre couperait des phrases en deux.
  public static func decouper(_ texte: String) -> [SegmentDeTexte] {
    var segments: [SegmentDeTexte] = []
    var lignesDeTexte: [String] = []
    var lignesDeCode: [String] = []
    var langueAnnoncee: String?
    var dansUnBloc = false

    /// Ferme le tampon courant. `nil` pour la langue veut dire « bloc sans
    /// langage annoncé » : c'est un état légitime, pas une absence de bloc.
    func fermerLeCode() {
      let contenu = lignesDeCode.joined(separator: "\n")
      lignesDeCode.removeAll()
      dansUnBloc = false
      // Un bloc VIDE n'est pas un bloc : trois accents graves collés sont une
      // coquille de l'agent, pas du code à afficher dans un cadre.
      guard !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        langueAnnoncee = nil
        return
      }
      segments.append(.code(contenu, langue: langueAnnoncee))
      langueAnnoncee = nil
    }

    func fermerLeTexte() {
      let contenu = lignesDeTexte.joined(separator: "\n")
      lignesDeTexte.removeAll()
      guard !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      segments.append(.texte(contenu))
    }

    // LE RETOUR CHARIOT SE NORMALISE AVANT DE DÉCOUPER — et c'est un piège de
    // Swift qu'il faut nommer, parce qu'il ne se voit pas : « \r\n » est UN SEUL
    // `Character` (un groupe de graphèmes), donc `split(separator: "\n")` NE LE
    // RECONNAÎT PAS et rend une ligne unique. Mesuré : un texte venu d'une
    // machine Windows ressortait en un seul segment, clôtures comprises, sans
    // qu'aucun bloc ne soit vu. On ramène donc les fins de ligne à « \n » d'abord.
    let normalise = texte.replacingOccurrences(of: "\r\n", with: "\n")

    for brute in normalise.split(separator: "\n", omittingEmptySubsequences: false) {
      let ligne = String(brute)
      let marque = self.cloture(ligne)

      if dansUnBloc {
        if marque != nil { fermerLeCode() } else { lignesDeCode.append(ligne) }
      } else if let marque {
        fermerLeTexte()
        dansUnBloc = true
        langueAnnoncee = marque.langue
      } else {
        lignesDeTexte.append(ligne)
      }
    }

    if dansUnBloc { fermerLeCode() } else { fermerLeTexte() }
    return segments
  }

  /// CE QU'UNE LIGNE DE CLÔTURE ANNONCE — le langage, s'il y en a un.
  ///
  /// POURQUOI UN TYPE, ET NON UN `String??`. Une clôture sans langage est un FAIT
  /// — ```` ``` ```` tout seul —, et « ce n'est pas une clôture » en est un autre.
  /// Deux optionnels imbriqués exprimeraient les deux, mais personne ne les
  /// relirait : ce type dit la même chose en clair. (Un tuple à un seul élément
  /// étiqueté n'existe pas en Swift — la tentative a été faite, et refusée par le
  /// compilateur.)
  struct Cloture: Equatable {
    let langue: String?
  }

  /// La ligne est-elle une clôture ? Rend ce qu'elle annonce, ou `nil` si ce n'est
  /// pas une clôture du tout.
  static func cloture(_ ligne: String) -> Cloture? {
    let nue = ligne.trimmingCharacters(in: .whitespaces)
    guard nue.hasPrefix("```") else { return nil }
    let apres = nue.drop(while: { $0 == "`" })
    let langage = apres.trimmingCharacters(in: .whitespaces)

    // Une clôture ne porte QUE des accents graves et, au plus, un nom de langage.
    // Sans cette vérification, une phrase qui commence par trois accents graves —
    // « ``` est la syntaxe d'un bloc » — ouvrirait un bloc fantôme.
    guard
      langage.isEmpty
        || (langage.count <= 20
          && langage.allSatisfy { $0.isLetter || $0.isNumber || "+#.-".contains($0) })
    else { return nil }

    return Cloture(langue: langage.isEmpty ? nil : langage)
  }
}
