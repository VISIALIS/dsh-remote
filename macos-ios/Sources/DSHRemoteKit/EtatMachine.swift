import SwiftUI

/// CE QU'ON DIT D'UNE MACHINE — le même fait, dans les mêmes mots, partout.
///
/// POURQUOI UNE SOURCE UNIQUE. Le panneau latéral et la page disaient le même
/// état avec des mots différents : « hors ligne » sous la vignette, « hors ligne
/// sur le tailnet » sous le titre de la page ; « pas de DSH » d'un côté, « en
/// ligne · pas de DSH » de l'autre. Deux vocabulaires pour un seul fait obligent
/// le lecteur à traduire — et finissent par diverger, chacun évoluant de son côté.
///
/// La vignette ABRÈGE (`court: true`) parce qu'elle tient en 68 points ; la page
/// dit la phrase entière. Les MOTS sont les mêmes, et c'est ce que ce type
/// garantit — un test l'éprouve.
///
/// CE QUE LE `Ton` NE DIT PAS. Il exprime la gravité **pour l'usage de DSH** :
/// « pas de DSH » est orange, parce que la machine ne peut pas servir
/// l'application. La PASTILLE de la vignette, elle, garde son sens propre et
/// documenté (vert = la machine répond), qui n'est pas celui-ci : une machine en
/// ligne sans DSH y est verte avec la légende « pas de DSH ». Les deux lectures
/// sont voulues, et chacune est écrite là où elle vit.
enum EtatMachine {
  /// La gravité, qui décide de la couleur — et elle seule.
  enum Ton {
    case pret
    case attente
    case inconnu
  }

  struct Description: Equatable {
    let texte: String
    let symbole: String
    let ton: Ton
  }

  /// L'état d'une machine, en une ligne.
  ///
  /// - Parameters:
  ///   - enLigne: ce que Tailscale dit de la machine.
  ///   - sertDsh: le verdict de la sonde — `nil` = pas encore su.
  ///   - estLocal: la machine qui a répondu est celle qui interroge.
  ///   - court: la forme de la vignette (68 points) plutôt que la phrase entière.
  static func decrire(enLigne: Bool, sertDsh: Bool?, estLocal: Bool, court: Bool) -> Description {
    guard enLigne else {
      return Description(texte: L("hors ligne"), symbole: "moon.zzz.fill", ton: .attente)
    }
    switch sertDsh {
    case true:
      return Description(
        // LES QUATRE FORMES PASSENT PAR `L`, y compris les deux qui n'étaient que
        // des ternaires : « hôte » est un mot de l'interface, et la vignette
        // l'affichait en français dans une application anglaise.
        texte: court
          ? (estLocal ? L("DSH · hôte") : L("DSH"))
          : (estLocal ? L("DSH · hôte interrogé") : L("DSH")),
        symbole: "checkmark.seal.fill",
        ton: .pret)
    case false:
      return Description(
        texte: L("pas de DSH"), symbole: "exclamationmark.triangle.fill", ton: .attente)
    case nil:
      return Description(texte: L("vérification…"), symbole: "clock", ton: .inconnu)
    }
  }

  /// CE QUE VOIXOVER ANNONCE POUR UNE MACHINE — le nom, puis l'état ENTIER.
  ///
  /// POURQUOI IL EST ICI. Le libellé de la vignette disait « en ligne » ou
  /// « hors ligne » et s'arrêtait là : une machine EN LIGNE qui ne sert PAS DSH
  /// était donc annoncée « MacMini, en ligne » — soit l'inverse de ce qu'il faut
  /// savoir avant d'appuyer, puisque l'appui ne donnera rien. Le verdict
  /// existait pourtant déjà, mais en couleur et en abrégé, deux choses qu'un
  /// lecteur d'écran ne rend pas.
  ///
  /// La phrase est construite À PARTIR DE `decrire` : elle ne peut donc pas
  /// diverger des mots affichés, et elle s'éprouve sans rendre une vue.
  static func libelleAccessible(
    nom: String, enLigne: Bool, sertDsh: Bool?, estLocal: Bool
  ) -> String {
    let etat = decrire(enLigne: enLigne, sertDsh: sertDsh, estLocal: estLocal, court: false)
    return "\(nom), \(etat.texte)"
  }

  /// LA CONCLUSION DU DIAGNOSTIC, en une phrase.
  ///
  /// POURQUOI ELLE EST ICI, ET NON DANS LA VUE. Elle décide de trois choses à la
  /// fois — le texte, le symbole et la gravité —, et la page en donnait trois
  /// formulations du même fait : un sous-titre, un bandeau rouge, et le résumé du
  /// parcours. Une fonction pure se teste ; une vue, non.
  ///
  /// Le nom de la machine n'est PAS répété : il est juste au-dessus, en titre.
  static func conclusion(enLigne: Bool, etapes: [EtapesServeur.Etape]) -> Description {
    guard enLigne else {
      return Description(
        texte: L("Rien ne peut être joint sur cette machine tant qu'elle est hors ligne sur le tailnet."),
        symbole: "moon.zzz.fill",
        ton: .attente)
    }
    if etapes.allSatisfy({ $0.etat == .franchie }) {
      return Description(
        texte: EtapesServeur.resume(etapes), symbole: "checkmark.seal.fill", ton: .pret)
    }
    if etapes.contains(where: { $0.etat == .aFaire }) {
      return Description(
        texte: EtapesServeur.resume(etapes),
        symbole: "exclamationmark.triangle.fill",
        ton: .attente)
    }
    // Ni franchi, ni su : c'est le cas de la sonde en cours, et il ne mérite ni
    // le vert ni l'orange — annoncer l'un ou l'autre serait affirmer.
    return Description(texte: EtapesServeur.resume(etapes), symbole: "clock", ton: .inconnu)
  }
}

extension EtatMachine.Ton {
  /// La couleur d'un ton. Elle est décidée ICI, une fois : trois vues s'en
  /// servent, et trois tables de couleurs auraient fini par diverger.
  var couleur: Color {
    switch self {
    case .pret: return .green
    case .attente: return .orange
    case .inconnu: return .secondary
    }
  }
}

/// LA PASTILLE D'ÉTAT D'UNE MACHINE — un état, une couleur, un mot.
///
/// POURQUOI UNE PASTILLE, ET UNE SEULE. La page disait l'état de la machine à
/// quatre endroits : sous le titre, dans un bandeau rouge, dans le résumé du
/// diagnostic, et implicitement dans le titre de l'étape 2. Quatre fois le même
/// fait, sans progression — le lecteur ne sait plus lequel croire. Un état se dit
/// une fois, à l'endroit où on le cherche : en tête.
///
/// `PastilleEtat` existe déjà, et c'est celle d'une SESSION : deux pastilles,
/// deux sujets — le nom dit lequel.
struct PastilleDeMachine: View {
  let description: EtatMachine.Description

  var body: some View {
    Label(description.texte, systemImage: description.symbole)
      .font(.caption.weight(.medium))
      .foregroundStyle(description.ton.couleur)
      .padding(.horizontal, 9)
      .padding(.vertical, 3)
      .background(description.ton.couleur.opacity(0.14), in: Capsule())
      .fixedSize(horizontal: false, vertical: true)
  }
}
