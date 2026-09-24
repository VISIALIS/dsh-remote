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
  /// Les langues servies. L'anglais est la langue du projet : c'est elle qui
  /// s'affiche, sauf si le système demande le français.
  public static let langues = ["en", "fr"]

  /// `fr` seulement quand la langue préférée du système est le français.
  /// Toute autre langue, y compris l'absence de préférence, reste en anglais.
  public static func langueDemandee() -> String {
    let preferee = Locale.preferredLanguages.first?.lowercased() ?? "en"
    return preferee.hasPrefix("fr") ? "fr" : "en"
  }

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

  /// ANCRE DE PAQUET — une classe, et rien d'autre : `Bundle(for:)` en exige une.
  ///
  /// POURQUOI ELLE EXISTE. C'est le seul moyen de demander à l'exécution « dans
  /// quel paquet ce code a-t-il été chargé ? », et donc de trouver le paquet de
  /// ressources SANS deviner la forme du dossier de construction. Sous
  /// `swift test`, elle désigne le paquet de tests, dont le dossier parent est
  /// celui des produits — exactement là où SwiftPM dépose le `.bundle`.
  private final class AncreDePaquet {}

  /// LE PAQUET DE RESSOURCES, CHERCHÉ AUX ENDROITS PLAUSIBLES — et pourquoi pas
  /// `Bundle.module`.
  ///
  /// DÉFAUT RÉEL, MESURÉ. Le paquet macOS installé ne contenait AUCUNE table de
  /// traduction : le script d'empaquetage copiait le binaire et l'icône, pas le
  /// `<Paquet>_<Cible>.bundle` où vivent les `.strings`. L'anglais ne tenait donc
  /// qu'à un CHEMIN ABSOLU du dossier de construction — le repli de l'accesseur
  /// engendré par SwiftPM :
  ///
  ///     let buildPath = "/Users/<qui-a-compile>/.build/…/DSHRemote_DSHRemoteKit.bundle"
  ///
  /// Sur la machine qui avait compilé, tout allait bien. Ailleurs, `L()` et `T()`
  /// retombaient sur la CLÉ — c'est-à-dire sur la phrase française : une
  /// application annoncée bilingue s'affichait en français, sans erreur.
  ///
  /// ET CE N'EST PAS SEULEMENT LA LECTURE DES TABLES QUI EN DÉPEND : `L()` et
  /// `T()` y passaient AUSSI (`bundle: .module`), donc le plantage arrivait au
  /// premier mot traduit — au lancement de l'application, sur une machine où le
  /// dossier de construction n'existe pas. Reproduit, trace à l'appui.
  ///
  /// POURQUOI ON NE PEUT PAS SE CONTENTER DE `Bundle.module`, ET POURQUOI CE N'EST
  /// PAS SEULEMENT UNE QUESTION DE COPIE. L'accesseur cherche d'abord à la RACINE
  /// du `.app`, seul endroit d'où il accepte un voisinage de `Contents/` — or
  /// `codesign` REFUSE un paquet dont la racine porte autre chose que `Contents/`
  /// (« unsealed contents present in the bundle root », mesuré). La bonne place
  /// dans un paquet signé est `Contents/Resources/`, que l'accesseur ne regarde
  /// pas. On cherche donc soi-même, dans l'ordre, et on n'échoue JAMAIS : sans
  /// tables, l'application parle français — c'est le repli documenté, pas un
  /// plantage.
  private static let paquetDeRessources: Bundle? = {
    let nom = "DSHRemote_DSHRemoteKit.bundle"
    let principaux = Bundle.main
    var candidats: [URL] = []
    // 1. `Contents/Resources/` — la place CORRECTE dans un `.app` signé. Sur iOS,
    //    le paquet est plat et `resourceURL` est sa racine : c'est aussi la bonne
    //    réponse.
    if let ressources = principaux.resourceURL {
      candidats.append(ressources.appendingPathComponent(nom))
    }
    // 2. La racine du paquet, et le dossier du binaire : ce que SwiftPM engendre
    //    pour un exécutable nu (`swift run`).
    candidats.append(principaux.bundleURL.appendingPathComponent(nom))
    candidats.append(principaux.bundleURL.deletingLastPathComponent().appendingPathComponent(nom))

    // 3. LE DOSSIER DE CONSTRUCTION, DÉDUIT DU CHEMIN DE CE FICHIER — pour
    //    `swift test` et `swift run`, où `Bundle.main` n'est PAS dans l'arbre du
    //    paquet (mesuré : c'est le `xctest` de la chaîne d'outils). On ne peut pas
    //    se servir de `Bundle.module` à la place : son repli est un `fatalError`,
    //    donc un plantage au premier mot traduit — précisément ce que cette
    //    fonction existe pour éviter.
    //
    //    Ces candidats ne valent que sur une machine qui a les SOURCES : ailleurs
    //    ils ne trouvent rien, et l'application parle français. C'est le repli
    //    voulu, et il est silencieux pour l'utilisateur d'un paquet correct.
    let racine = URL(fileURLWithPath: #filePath)  // …/Sources/DSHRemoteKit/Traduction.swift
      .deletingLastPathComponent()  // …/Sources/DSHRemoteKit
      .deletingLastPathComponent()  // …/Sources
      .deletingLastPathComponent()  // …/<racine du paquet>
    var deDeveloppement: [URL] = []

    // 3 bis. LE PAQUET QUI PORTE CE CODE, ET SON VOISIN. `Bundle(for:)` exige une
    //    CLASSE : elle est là pour ça, et rien d'autre.
    //
    //    POURQUOI CE CANDIDAT EST LE MEILLEUR DES QUATRE. Sous `swift test`, il
    //    désigne le paquet de TESTS (`…/DSHRemoteKitTests.xctest`), dont le
    //    dossier parent est EXACTEMENT celui où SwiftPM dépose le paquet de
    //    ressources — quelle que soit la forme du dossier de construction. Les
    //    chemins devinés plus bas, eux, dépendent de la chaîne d'outils — et ce
    //    dépôt est utilisé depuis DEUX Mac, qui ne l'ont pas la même. Mesuré :
    //    `swift build --show-bin-path` rend `.build/out/Products/Debug` avec
    //    Swift 6.4 / Xcode 27, et `.build/arm64-apple-macosx/debug` avec
    //    Swift 6.3.3 / Xcode 26.6. Les deux formes sont donc des candidats, et
    //    c'est le `Bundle(for:)` ci-dessus qui répond sans dépendre d'aucune :
    //    la mauvaise forme ne casse pas l'application, elle rend `cles()` muet,
    //    donc fait échouer les tests de parité des traductions — ce qui est
    //    précisément arrivé, sur une seule des deux machines.
    let ancre = Bundle(for: AncreDePaquet.self).bundleURL.deletingLastPathComponent()
    deDeveloppement.append(ancre.appendingPathComponent(nom))

    // 4. LES FORMES DEVINÉES, par architecture et par configuration : elles
    //    couvrent `swift run` et les chaînes d'outils plus anciennes.
    for configuration in ["Debug", "Release"] {
      deDeveloppement.append(
        racine.appendingPathComponent(".build/out/Products/\(configuration)/\(nom)"))
    }
    for architecture in ["arm64-apple-macosx", "x86_64-apple-macosx"] {
      for configuration in ["debug", "release"] {
        deDeveloppement.append(
          racine.appendingPathComponent(".build/\(architecture)/\(configuration)/\(nom)"))
      }
    }

    for candidat in candidats + deDeveloppement {
      // `fileExists` ÉVITE DE DEMANDER À `Bundle` UN CHEMIN QUI N'EXISTE PAS : sur
      // un paquet installé ailleurs, les quatre candidats de développement
      // échouent, et c'est le cas NORMAL — pas une anomalie à signaler.
      guard FileManager.default.fileExists(atPath: candidat.path) else { continue }
      if let paquet = Bundle(url: candidat) { return paquet }
    }
    return nil
  }()

  /// LE PAQUET OÙ LIRE UNE PHRASE — celui qu'on a résolu, sinon le paquet principal.
  ///
  /// POURQUOI CE REPLI EST LE PAQUET PRINCIPAL, ET PAS `Bundle.module`. L'accesseur
  /// engendré par SwiftPM **plante** (`fatalError`) quand ni la racine du `.app` ni
  /// le dossier de construction ne portent le paquet de ressources — reproduit :
  /// `L()` appelée au lancement, `EXC_BREAKPOINT` dans
  /// `resource_bundle_accessor.swift:12`. Une traduction manquante ne doit pas tuer
  /// l'application : elle doit la faire parler français, ce qui est exactement ce
  /// qui se passe quand on cherche dans le paquet principal — la CLÉ est la phrase
  /// française (voir l'en-tête de ce fichier).
  static var paquet: Bundle { paquetDeRessources ?? .main }

  /// La table d'une langue, lue depuis le paquet de ressources.
  ///
  /// Rend `nil` — et l'appelant retombe alors sur la clé — quand le paquet est
  /// absent ou incomplet : c'est le repli documenté, et il vaut mieux que mourir
  /// au lancement pour une traduction manquante.
  private static func table(_ langue: String) -> [String: String]? {
    guard let paquet = paquetDeRessources,
      let chemin = paquet.path(forResource: langue, ofType: "lproj"),
      let dossier = Bundle(path: chemin),
      let url = dossier.url(forResource: "Localizable", withExtension: "strings"),
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
public func T(_ cle: String) -> Text {
  Text(verbatim: L(cle))
}

/// La CHAÎNE d'une clé, localisée — pour les endroits qui prennent un `String`.
///
/// POURQUOI ELLE EXISTE SÉPARÉMENT. `Button`, `Toggle` et `Section` n'offrent pas
/// d'initialiseur qui accepte un `Text` ET un paquet : leurs variantes à
/// `LocalizedStringKey` cherchent dans le programme principal. Leur donner une
/// `String` DÉJÀ TRADUITE est le seul chemin qui traverse le paquet — et c'est
/// aussi ce qu'il faut au modèle, dont les messages sont construits en `String`
/// avant d'être affichés.
public func L(_ cle: String) -> String {
  let langue = Traduction.langueDemandee()
  if let valeur = Traduction.texte(cle, langue: langue) { return valeur }
  if langue != "en", let anglais = Traduction.texte(cle, langue: "en") { return anglais }
  return cle
}
