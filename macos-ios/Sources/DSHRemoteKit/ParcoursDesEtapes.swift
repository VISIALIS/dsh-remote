import SwiftUI

/// L'AFFICHAGE D'UN PARCOURS : l'étape qui bloque, et celles qu'on ne peut pas
/// encore franchir.
///
/// POURQUOI CETTE VUE EST PARTAGÉE. La page d'un serveur et la page « Ajouter un
/// serveur » affichent le même parcours, à la méthode près : l'une juge une
/// machine connue, l'autre liste le travail pour un Mac qu'on n'a pas encore.
/// Deux copies de cette mise en page auraient divergé — et c'est précisément ce
/// que l'utilisateur compare.
///
/// LA RÈGLE DEMANDÉE PAR LE PROPRIÉTAIRE : « si une étape de goal n'est pas
/// réalisée, les goals suivants sont grisés (pas besoin de rentrer dans leur
/// détail) ». Une seule frontière à la fois, donc :
///
///   - les étapes FRANCHIES : leur titre, et rien d'autre ;
///   - la PREMIÈRE non franchie : son explication et sa méthode — c'est elle
///     qu'on peut faire maintenant ;
///   - les SUIVANTES : grisées, sans explication ni commande. Leur mode d'emploi
///     n'aiderait pas : il suppose la précédente franchie, et l'afficher noierait
///     celle qui bloque.
struct ParcoursDesEtapes<Methode: View>: View {
  let etapes: [EtapesServeur.Etape]
  /// La méthode à afficher pour la seule étape qui n'est pas verrouillée.
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
    // LE VERROU SE DÉDUIT DE LA LISTE, jamais d'un champ de l'étape : c'est la
    // même règle pour les deux pages, et elle vit dans `EtapesServeur` où elle
    // est éprouvée.
    let verrouillee = EtapesServeur.estVerrouillee(etape, dans: etapes)

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
