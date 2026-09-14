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
  struct Description: Equatable {
    let texte: String
    let symbole: String
    let ton: EtatVisuel
  }

  /// L'état d'une machine, en une ligne.
  ///
  /// - Parameters:
  ///   - enLigne: ce que Tailscale dit de la machine.
  ///   - sertDsh: le verdict de la sonde — `nil` = pas encore su.
  ///   - estLocal: la machine qui a répondu est celle qui interroge.
  ///   - appairage: où en est CET APPAREIL avec cette machine. Il ne change pas
  ///     ce que la machine EST — elle sert DSH, ou pas —, mais il change ce qu'on
  ///     peut en faire, et c'est pour cela qu'il est dit à côté et non à la place.
  ///   - court: la forme de la vignette (68 points) plutôt que la phrase entière.
  static func decrire(
    enLigne: Bool, sertDsh: Bool?, estLocal: Bool, appairage: EtapesServeur.EtatAppairage,
    court: Bool
  ) -> Description {
    guard enLigne else {
      return Description(texte: L("hors ligne"), symbole: "moon.zzz.fill", ton: .attention)
    }
    switch sertDsh {
    case true:
      // LA MACHINE SERT DSH — ET L'APPAIRAGE SE DIT À CÔTÉ, PAS À SA PLACE.
      //
      // Défaut corrigé, et c'est celui qui coûtait le plus cher : sans jeton
      // rangé, la sonde ne partait pas, et la vignette annonçait « pas de DSH ».
      // L'utilisateur partait donc installer un plugin DÉJÀ INSTALLÉ, sur une
      // machine parfaitement prête. Ce que la machine a, c'est DSH ; ce qui
      // manque est ailleurs, et le mot le dit.
      switch appairage {
      case .appaire:
        return Description(
          // LES QUATRE FORMES PASSENT PAR `L`, y compris les deux qui n'étaient que
          // des ternaires : « hôte » est un mot de l'interface, et la vignette
          // l'affichait en français dans une application anglaise.
          texte: court
            ? (estLocal ? L("DSH · hôte") : L("DSH"))
            : (estLocal ? L("DSH · hôte interrogé") : L("DSH")),
          symbole: "checkmark.seal.fill",
          ton: .pret)
      case .absent:
        return Description(texte: L("à appairer"), symbole: "qrcode", ton: .pret)
      case .refuse:
        return Description(
          texte: L("jeton refusé"), symbole: "key.slash", ton: .attention)
      }
    case false:
      return Description(
        texte: L("pas de DSH"), symbole: "exclamationmark.triangle.fill", ton: .attention)
    case nil:
      return Description(texte: L("vérification…"), symbole: "clock", ton: .attente)
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
    nom: String, enLigne: Bool, sertDsh: Bool?, estLocal: Bool,
    appairage: EtapesServeur.EtatAppairage
  ) -> String {
    let etat = decrire(
      enLigne: enLigne, sertDsh: sertDsh, estLocal: estLocal, appairage: appairage, court: false)
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
        ton: .attention)
    }
    if etapes.allSatisfy({ $0.etat == .franchie }) {
      return Description(
        texte: EtapesServeur.resume(etapes), symbole: "checkmark.seal.fill", ton: .pret)
    }
    if etapes.contains(where: { $0.etat == .aFaire }) {
      return Description(
        texte: EtapesServeur.resume(etapes),
        symbole: "exclamationmark.triangle.fill",
        ton: .attention)
    }
    // Ni franchi, ni su : c'est le cas de la sonde en cours, et il ne mérite ni
    // le vert ni l'orange — annoncer l'un ou l'autre serait affirmer.
    return Description(texte: EtapesServeur.resume(etapes), symbole: "clock", ton: .attente)
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
