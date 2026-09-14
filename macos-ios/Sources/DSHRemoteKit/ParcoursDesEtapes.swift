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
  ///
  /// Les cas vivent dans `EtapesServeur` (`Mode`) : ce qu'ils décident — ce qui
  /// est verrouillé, donc ce qui est atteignable — est une règle, et elle est
  /// éprouvée là-bas.
  typealias Mode = EtapesServeur.Mode

  let etapes: [EtapesServeur.Etape]
  var mode: Mode = .diagnostic
  /// Dessiner la carte (fond et rembourrage), ou seulement les lignes ?
  ///
  /// POURQUOI CE DRAPEAU. Sur la page d'un serveur, la CONCLUSION du diagnostic
  /// appartient au même bloc que les constats : c'est une seule carte, et c'est
  /// donc la page qui la dessine. La page « Ajouter un serveur », elle, n'a pas
  /// de conclusion à y mettre et garde sa carte ici.
  var encadre: Bool = true
  /// La méthode à afficher pour une étape non franchie.
  ///
  /// Elle reçoit l'ÉTAPE, et pas seulement son numéro : la page a besoin de son
  /// état pour choisir entre la méthode complète (« à faire ») et la seule
  /// commande de constat (« inconnue »).
  @ViewBuilder var methode: (EtapesServeur.Etape) -> Methode

  var body: some View {
    if encadre {
      contenu
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    } else {
      contenu
    }
  }

  private var contenu: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(etapes, id: \.numero) { etape in
        ligne(etape)
      }
    }
  }

  private func ligne(_ etape: EtapesServeur.Etape) -> some View {
    // LE VERROU SE DÉDUIT DE LA LISTE, jamais d'un champ de l'étape : la règle
    // vit dans `EtapesServeur`, où elle est éprouvée. Il ne s'applique QU'AUX
    // OBJECTIFS : un diagnostic n'a pas de frontière. Et il rend LE NUMÉRO de
    // l'étape qui bloque — pas « la précédente », qui n'est pas la même sur une
    // liste de travail (l'appairage n'est bloqué que par Tailscale).
    let bloquante = mode == .objectifs
      ? EtapesServeur.etapeQuiBloque(etape, dans: etapes, mode: mode) : nil
    let verrouillee = bloquante != nil
    let presentation = EtapesServeur.presentation(etape, dans: etapes, mode: mode)

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: verrouillee ? "lock" : symbole(etape.etat))
          .foregroundStyle(verrouillee ? Color.secondary.opacity(0.5) : couleur(etape.etat))
        Text("\(etape.numero). \(etape.titre)")
          .font(.callout.weight(etape.etat == .franchie || verrouillee ? .regular : .medium))
          .foregroundStyle(couleurDuTitre(etape, verrouillee: verrouillee))
          .fixedSize(horizontal: false, vertical: true)
        // DE QUELLE MACHINE PARLE CETTE ÉTAPE — et seulement là où ça se perd.
        //
        // Sur la page d'une machine, le titre dit déjà de laquelle il s'agit, et
        // trois lignes « sur le Mac » y seraient du bruit. Sur une LISTE DE
        // TRAVAIL, il n'y a aucune machine nommée : les étapes du Mac et celles
        // de l'appareil s'y mélangent, et c'est ainsi qu'on finit par taper une
        // commande sur le mauvais ordinateur. Le repère coûte deux mots, et il
        // les vaut.
        if mode == .objectifs, etape.responsable == .hote {
          T("sur le Mac")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        Spacer(minLength: 4)
        if let bloquante {
          Text(L("après l'étape") + " \(bloquante)")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else if etape.etat == .inconnue {
          T("à vérifier")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      // LA LIGNE SE LIT D'UN BLOC SOUS VOIXOVER : numéro, titre, état. Sans
      // cela, un lecteur d'écran énumère trois fragments dont aucun ne dit si
      // l'étape est faite, à faire, ou seulement verrouillée.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(libelle(etape, bloquante: bloquante))

      // ON N'EXPLIQUE ET N'OUTILLE QUE CE QUI RESTE À FAIRE — mais on l'outille
      // TOUJOURS. Une étape verrouillée garde son explication et sa méthode,
      // repliées : le verrou dit l'ORDRE, il ne ferme plus la porte.
      if presentation != .rien {
        Text(etape.explication)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(verrouillee ? 0.7 : 1)
        // LA MÉTHODE DE LA FRONTIÈRE EST OUVERTE ; CELLES DES AUTRES SE DÉPLIENT.
        //
        // POURQUOI. Un diagnostic DIT tout, mais il n'OUTILLE qu'une chose à la
        // fois : trois jeux de commandes à l'écran noient celle qui est
        // exécutable maintenant, et les deux autres supposent de toute façon la
        // première franchie. Les constats restent donc tous visibles — c'est la
        // règle, et elle ne bouge pas —, seule la marche à suivre se replie.
        if presentation == .ouverte {
          methode(etape)
        } else {
          DisclosureGroup {
            methode(etape)
              .padding(.top, 6)
          } label: {
            Text(verrouillee ? "Voir la méthode" : "Méthode")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  /// CE QU'ANNONCE VOIXOVER POUR UNE LIGNE D'ÉTAPE.
  ///
  /// « verrouillée » n'est pas un état de l'étape mais une conséquence de
  /// l'ordre : on le dit APRÈS l'état, et seulement là où il s'applique.
  ///
  /// LE REPÈRE « SUR LE MAC » Y EST AUSSI, quand il est affiché. Un lecteur
  /// d'écran ne voit pas la couleur discrète qui distingue les deux machines :
  /// sans ce mot, il entend cinq étapes de suite sans savoir lesquelles se font
  /// ailleurs — exactement ce que le repère visuel répare.
  private func libelle(_ etape: EtapesServeur.Etape, bloquante: Int?) -> String {
    let etat: String
    switch etape.etat {
    case .franchie: etat = "franchie"
    case .aFaire: etat = "à faire"
    case .inconnue: etat = "à vérifier"
    }
    let ou = mode == .objectifs && etape.responsable == .hote ? ", sur le Mac" : ""
    let ordre = bloquante.map { ", après l'étape \($0)" } ?? ""
    return "Étape \(etape.numero), \(etape.titre)\(ou), \(etat)\(ordre)"
  }

  private func symbole(_ etat: EtapesServeur.Etat) -> String {
    switch etat {
    case .franchie: return "checkmark.circle.fill"
    case .aFaire: return "circle"
    case .inconnue: return "questionmark.circle"
    }
  }

  private func couleur(_ etat: EtapesServeur.Etat) -> Color {
    // LA COULEUR D'UN ÉTAT SE DÉCIDE DANS `EtatVisuel`, jamais ici.
    etatVisuel(etat).couleur
  }

  /// L'état d'une étape, dans le vocabulaire commun aux deux surfaces.
  private func etatVisuel(_ etat: EtapesServeur.Etat) -> EtatVisuel {
    switch etat {
    case .franchie: return .pret
    case .aFaire: return .attention
    case .inconnue: return .attente
    }
  }

  private func couleurDuTitre(_ etape: EtapesServeur.Etape, verrouillee: Bool) -> Color {
    if verrouillee { return Color.secondary.opacity(0.6) }
    return etape.etat == .franchie ? Color.secondary : Color.primary
  }
}
