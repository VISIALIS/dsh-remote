import Foundation
import SwiftUI

/// LA TRADUCTION, ET LA LANGUE DEMANDÉE — la charpente qui rend les tables éprouvables.
///
/// POURQUOI CE TYPE EXISTE. Les tables vivent dans le paquet de la bibliothèque
/// (`Bundle.module`, voir `Package.swift`), et **rien ne dit à la compilation**
/// qu'une clé existe en français ET en anglais. Une clé oubliée se traduit par la
/// clé elle-même — c'est-à-dire par du FRANÇAIS dans une interface anglaise —, et
/// cela ne se voit qu'à l'usage, dans une langue qu'on ne parle pas forcément.
/// Deux tests tiennent donc la parité des tables, et ils ont besoin de pouvoir
/// LIRE les tables par langue : c'est tout ce que ce type ajoute.
///
/// POURQUOI LE FRANÇAIS EST LA SOURCE, ET NON UNE TRADUCTION PARMI D'AUTRES. Les
/// clés SONT les phrases françaises : ce qui se lit dans le code est ce qui
/// s'affiche, une clé manquante se voit à l'écran plutôt qu'en test, et la RÈGLE
/// #1 du dépôt — tout en français — reste vraie pour le code, les commentaires et
/// les clés. L'anglais est une traduction AJOUTÉE.
public enum Traduction {
  /// Les langues servies par ce paquet.
  ///
  /// L'ORDRE EST CELUI DE LA SOURCE : le français d'abord. Un test vérifie que
  /// les deux tables portent exactement les mêmes clés.
  public static let langues = ["fr", "en"]

  /// Le texte d'une clé dans une langue DONNÉE, ou `nil` si la clé n'y est pas.
  ///
  /// C'est la question que posent les tests — « que dirait l'anglais pour cette
  /// phrase ? » —, et elle se pose sans changer la langue de l'application.
  public static func texte(_ cle: String, langue: String) -> String? {
    table(langue)?[cle]
  }

  /// Toutes les clés d'une langue, ou `nil` si la table est introuvable.
  public static func cles(_ langue: String) -> Set<String>? {
    table(langue).map { Set($0.keys) }
  }

  /// La table d'une langue, lue depuis le paquet de la BIBLIOTHÈQUE.
  ///
  /// POURQUOI ON LA LIT À LA MAIN, ET POURQUOI C'EST UTILE AUSSI AUX TESTS.
  /// `Bundle.module` est l'accesseur engendré par SwiftPM pour les ressources de
  /// cette cible : c'est le seul endroit où les tables sont copiées, et le seul
  /// que les deux chaînes de construction — SwiftPM pour macOS, Xcode pour iOS —
  /// alimentent pareillement.
  private static func table(_ langue: String) -> [String: String]? {
    guard let chemin = Bundle.module.path(forResource: langue, ofType: "lproj"),
      let paquet = Bundle(path: chemin),
      let url = paquet.url(forResource: "Localizable", withExtension: "strings"),
      let lue = NSDictionary(contentsOf: url) as? [String: String]
    else { return nil }
    return lue
  }
}

// ── Les deux points d'entrée, et pourquoi ils sont COURTS ─────────────────────
//
// `T` et `L` apparaissent plus de cent cinquante fois dans les vues et le modèle.
// Leur brièveté est donc délibérée : `Traduction.texte(_:langue:)` à chaque site
// aurait noyé le code sous la mécanique de traduction, alors que ce qui compte à
// la lecture est la PHRASE. Les deux sont documentés ici, une fois.

/// Le TEXTE d'une clé, localisé dans le paquet de la bibliothèque.
///
/// POURQUOI LE PAQUET EST NOMMÉ EXPLICITEMENT. Mesuré : un littéral passé
/// directement à `Text` cherche dans le programme PRINCIPAL, où les tables de la
/// bibliothèque ne sont pas — l'interface restait alors en français même lancée
/// en anglais. `bundle: .module` désigne le paquet des ressources de cette cible,
/// celui que SwiftPM et Xcode alimentent pareillement.
///
/// La clé EST la phrase française (voir `Traduction`) : ce qui se lit dans le
/// code est ce qui s'affiche.
public func T(_ cle: String.LocalizationValue) -> Text {
  Text(String(localized: cle, bundle: .module))
}

/// La CHAÎNE d'une clé, localisée — pour les endroits qui prennent un `String`.
///
/// POURQUOI ELLE EXISTE SÉPARÉMENT. `Button`, `Toggle` et `Section` n'offrent pas
/// d'initialiseur qui accepte un `Text` ET un paquet : leurs variantes à
/// `LocalizedStringKey` cherchent dans le programme principal. Leur donner une
/// `String` DÉJÀ TRADUITE est le seul chemin qui traverse le paquet — et c'est
/// aussi ce qu'il faut au modèle, dont les messages sont construits en `String`
/// avant d'être affichés.
public func L(_ cle: String.LocalizationValue) -> String {
  String(localized: cle, bundle: .module)
}
