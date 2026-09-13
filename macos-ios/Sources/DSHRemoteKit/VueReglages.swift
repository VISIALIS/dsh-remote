import DSHRemoteKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// Réglages : ce qui n'est plus sur la page d'accueil.
///
/// POURQUOI CETTE FEUILLE EXISTE. L'adresse, le jeton, le test d'adresse et les
/// filtres occupaient plus de la moitié de la hauteur utile de la page
/// principale — pour des gestes qu'on fait une fois, puis plus jamais. La page
/// principale est redevenue ce qu'elle doit être : des appareils et des
/// sessions. Le reste descend d'un cran.
///
/// CE QUI N'A PAS LE DROIT D'ÊTRE PERDU EN CHEMIN. Chaque élément déplacé ici
/// corrigeait un défaut RÉEL, constaté sur l'iPhone :
///
///   - le champ du jeton est TOUJOURS visible. Il était auparavant masqué dès
///     qu'un jeton était présent, c'est-à-dire dès le PREMIER caractère saisi :
///     le champ disparaissait sous les doigts de l'utilisateur, qui ne pouvait
///     jamais terminer sa saisie ;
///   - le compte de caractères est affiché en clair. Un champ de 43 caractères
///     affiche des puces : sans ce compte, un jeton tronqué est indiscernable
///     d'un jeton complet, et le `401` qui suit accuse le serveur à tort ;
///   - le bouton « Coller » existe. 43 caractères en base64url, recopiés depuis
///     un terminal, ne se tapent pas à la main sur un clavier de téléphone ;
///   - « Tester l'adresse » dit ce qu'il a trouvé. C'est l'action qui a du sens
///     quand on a saisi une adresse à la main, et elle nomme son résultat —
///     « rien ne s'est passé » ne doit jamais être une réponse possible.
struct FeuilleReglages: View {
  @Bindable var modele: ModeleApp
  @Environment(\.dismiss) private var fermer

  var body: some View {
    NavigationStack {
      Form {
        Section {
          // ── CET ÉCRAN EST VOLONTAIREMENT VIDE POUR L'INSTANT ─────────────
          //
          // TOUT ce qui l'occupait est descendu sur la PAGE DE LA MACHINE
          // concernée : l'adresse, ses actions, le jeton — propre à chaque hôte,
          // mesuré — le diagnostic avec ses remèdes, ET les deux interrupteurs de
          // sessions. Ces derniers portent eux aussi sur une connexion :
          // « suivre l'activité » décide si l'on interroge CE serveur,
          // « chargées en mémoire seulement » filtre SA liste. Les garder ici
          // les faisait hériter d'une machine à l'autre.
          //
          // Il ne reste donc rien de général à régler. Le dire évite de croire à
          // un écran cassé : une feuille vide sans explication ressemble à un
          // défaut.
          Text("Les réglages généraux de l'application viendront ici. Tout ce qui concerne une machine — adresse, jeton, connexion, suivi, remèdes — se règle sur la page de cette machine, qu'on ouvre en touchant son icône.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .navigationTitle("Réglages")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Terminé") { fermer() }
        }
      }
    }
    #if os(macOS)
      // ── LA FEUILLE AVAIT LA LARGEUR DE SON CONTENU LE PLUS ÉTROIT ──────────
      //
      // POURQUOI CE CADRE EXISTE, ET POURQUOI IL EST LARGE. Sans lui, macOS
      // dimensionne la feuille sur la largeur IDÉALE du `Form` — de l'ordre de
      // 400 points — et tout ce qui dépasse est TRONQUÉ À DROITE. Constaté sur
      // la capture du propriétaire : la phrase d'aide de l'adresse s'arrêtait au
      // milieu d'un mot, celle des sessions aussi, et l'URL du tailnet était
      // coupée. Ce n'était pas un problème de texte, mais de place.
      //
      // 560 points est la largeur à laquelle une adresse de tailnet complète
      // (`http://` + machine + tailnet + `.ts.net`, une quarantaine de
      // caractères en chasse fixe) tient SANS troncature, boutons compris.
      .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity, minHeight: 560, idealHeight: 620)
      // `grouped` est le style des réglages macOS : sections encartées, en-têtes
      // en petites capitales, fond de fenêtre. Le style par défaut, lui, ressemble
      // à un formulaire de saisie — ce que ces réglages ne sont pas.
      .formStyle(.grouped)
    #endif
  }
}
