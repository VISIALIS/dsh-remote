import SwiftUI

/// L'AFFICHAGE DES ÉTAPES — en DIAGNOSTIC ou en OBJECTIFS.
///
/// DEUX LECTURES DU MÊME CONTENU, et c'est le propriétaire qui a fait la
/// distinction : « en fait les étapes pour la page détail, c'est un diagnostic de
/// santé ». Sur la page d'un serveur, les quatre lignes CONSTATENT l'état d'une
/// machine : on veut tout savoir d'un coup, y compris ce qui ne va pas, et rien
/// n'est « verrouillé » — un diagnostic qui cache la moitié de ses conclusions
/// n'est pas un diagnostic.
///
/// Sur la page « Ajouter un serveur », elles LISTENT un travail à faire, dans
/// l'ordre : là, une seule frontière à la fois, et les suivantes grisées —
/// « si une étape de goal n'est pas réalisée, les goals suivants sont grisés ».
///
/// POURQUOI LA VUE EST PARTAGÉE MALGRÉ TOUT. Le dessin d'une ligne est identique :
/// une icône d'état, un titre, une explication, une méthode. Seule la règle de
/// verrouillage change — et deux copies auraient divergé sur ce que l'utilisateur
/// compare d'une page à l'autre.
struct ParcoursDesEtapes<Methode: View>: View {

  /// COMMENT LIRE LES ÉTAPES : ce qu'on constate, ou ce qu'il reste à faire.
  enum Mode {
    /// Toutes les étapes sont montrées, avec leur méthode si elles ne sont pas
    /// franchies. Aucune n'est verrouillée : un diagnostic dit tout.
    case diagnostic
    /// Une seule frontière : les suivantes sont grisées, sans méthode.
    case objectifs
  }

  let etapes: [EtapesServeur.Etape]
  var mode: Mode = .diagnostic
  /// La méthode à afficher pour une étape non franchie.
  ///
  /// Elle reçoit l'ÉTAPE, et pas seulement son numéro : la page a besoin de son
  /// état pour choisir entre la méthode complète (« à faire ») et la seule
  /// commande de constat (« inconnue »).
  @ViewBuilder var methode: (EtapesServeur.Etape) -> Methode

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(etapes, id: \.numero) { etape in
        ligne(etape)
      }
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
  }

  private func ligne(_ etape: EtapesServeur.Etape) -> some View {
    // LE VERROU SE DÉDUIT DE LA LISTE, jamais d'un champ de l'étape : la règle
    // vit dans `EtapesServeur`, où elle est éprouvée. Il ne s'applique QU'AUX
    // OBJECTIFS : un diagnostic n'a pas de frontière.
    let verrouillee = mode == .objectifs && EtapesServeur.estVerrouillee(etape, dans: etapes)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: verrouillee ? "lock" : symbole(etape.etat))
          .foregroundStyle(verrouillee ? Color.secondary.opacity(0.5) : couleur(etape.etat))
        Text("\(etape.numero). \(etape.titre)")
          .font(.callout.weight(etape.etat == .franchie || verrouillee ? .regular : .medium))
          .foregroundStyle(couleurDuTitre(etape, verrouillee: verrouillee))
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 4)
        if verrouillee {
          Text("après l'étape \(etape.numero - 1)")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else if etape.etat == .inconnue {
          Text("à vérifier")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // ON N'EXPLIQUE ET N'OUTILLE QUE LA FRONTIÈRE. Ni les étapes franchies, ni
      // les verrouillées n'ont besoin d'un mode d'emploi ici.
      if etape.etat != .franchie && !verrouillee {
        Text(etape.explication)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        methode(etape)
      }
    }
  }

  private func symbole(_ etat: EtapesServeur.Etat) -> String {
    switch etat {
    case .franchie: return "checkmark.circle.fill"
    case .aFaire: return "circle"
    case .inconnue: return "questionmark.circle"
    }
  }

  private func couleur(_ etat: EtapesServeur.Etat) -> Color {
    switch etat {
    case .franchie: return .green
    case .aFaire: return .orange
    case .inconnue: return .secondary
    }
  }

  private func couleurDuTitre(_ etape: EtapesServeur.Etape, verrouillee: Bool) -> Color {
    if verrouillee { return Color.secondary.opacity(0.6) }
    return etape.etat == .franchie ? Color.secondary : Color.primary
  }
}
