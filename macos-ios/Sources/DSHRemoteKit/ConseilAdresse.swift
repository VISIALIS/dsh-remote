import Foundation

/// L'ADRESSE À CONSEILLER — le texte du champ, et pourquoi c'est celui-là.
///
/// POURQUOI CE TYPE EXISTE. Le champ d'adresse conseillait
/// `http://mon-mac.mon-tailnet.ts.net` sur iPhone sans condition, et le pied de
/// page présentait ce chemin comme le seul. Or `http://` vers un nom de domaine
/// n'est accepté que par un paquet qui porte une exception ATS ciblée — injectée
/// dans le `.app` CONSTRUIT depuis un fichier local non versionné. Un clone
/// produit donc une application qui refuse toutes les machines du tailnet en
/// `-1022`, pendant que l'écran continue de conseiller l'adresse fautive : le
/// remède prescrit était la cause de la panne.
///
/// CE QUI EST VRAI, ET QUI A ÉTÉ MESURÉ (sur le tailnet de la machine de
/// développement, le 13 septembre) :
///
/// | Adresse | Résultat |
/// |---|---|
/// | `http://<machine>.<tailnet>.ts.net` (port 80) | `404` — quelque chose répond : c'est le chemin publié par `tailscale serve` |
/// | `https://<machine>.<tailnet>.ts.net` (port 443) | `000` — rien n'écoute : HTTPS n'est pas publié sur ce tailnet |
/// | `http://100.x.y.z:3080` | `000` — le harness n'écoute QUE sur la boucle locale |
///
/// Il n'y a donc pas de « bonne adresse » universelle : il y a ce que CE paquet
/// autorise et ce que LE SERVEUR publie. Le conseil dit les deux, et l'adresse
/// littérale n'est plus proposée — elle ne répond pas.
///
/// LE CONSEIL NE DEVINE RIEN : il lit l'Info.plist du paquet en cours
/// (`ExceptionATS`). Deux paquets du même code peuvent donc conseiller deux
/// choses différentes, et c'est exactement ce qu'on veut — c'est la différence
/// entre celui qui peut joindre le tailnet et celui qui ne peut pas.
public struct ConseilAdresse: Equatable, Sendable {
  /// Le texte gris du champ vide : une FORME d'adresse, pas une adresse réelle.
  public let exemple: String
  /// Le pied de section : ce que l'adresse doit être, et ce que ce paquet accepte.
  public let aide: String
  /// Non `nil` quand l'adresse SAISIE ne peut pas marcher ici, avant même
  /// l'essai : le dire tôt évite de chercher une panne réseau là où le refus est
  /// déjà certain.
  public let avertissement: String?

  public init(exemple: String, aide: String, avertissement: String? = nil) {
    self.exemple = exemple
    self.aide = aide
    self.avertissement = avertissement
  }

  /// LA PLATEFORME, EN PARAMÈTRE ET NON EN `#if` SEUL.
  ///
  /// POURQUOI. Le conseil d'iOS est celui qui a été corrigé, et il ne peut pas
  /// être éprouvé depuis macOS si la seule façon de le choisir est une
  /// compilation conditionnelle : le test ne verrait que la branche du Mac. Le
  /// choix est donc une valeur, lisible et testable des deux côtés.
  public enum Plateforme: Equatable, Sendable {
    case mac
    case iOS

    /// Celle sur laquelle ce code est compilé.
    public static var courante: Plateforme {
      #if os(macOS)
        return .mac
      #else
        return .iOS
      #endif
    }
  }

  /// Le conseil pour une adresse en cours de saisie.
  public static func pour(
    adresse: String, plist: [String: Any]?, plateforme: Plateforme = .courante
  ) -> ConseilAdresse {
    let refus = avertissement(adresse: adresse, plist: plist, plateforme: plateforme)
    switch plateforme {
    case .mac:
      // SUR LE MAC, L'ADRESSE LOCALE EST LA BONNE, et elle est exemptée d'ATS :
      // c'est une IP littérale. Tailscale n'entre en jeu que pour viser une
      // AUTRE machine — d'où la phrase qui explique les deux cas plutôt qu'une
      // seule adresse présentée comme universelle.
      return ConseilAdresse(
        exemple: "http://127.0.0.1:3080",
        aide: """
          Le harness écoute sur la boucle locale de cette machine : \
          `http://127.0.0.1:3080` est l'adresse de ce Mac-ci. Pour viser une \
          AUTRE machine du tailnet, c'est son nom MagicDNS, sans port, publié par \
          `tailscale serve` — `tailscale serve status` l'affiche.
          """,
        avertissement: refus)
    case .iOS:
      if porteUneException(plist) {
        return ConseilAdresse(
          exemple: "http://mac-mini.mon-tailnet.ts.net",
          aide: """
            Le nom MagicDNS de la machine, publié par `tailscale serve` : \
            `tailscale serve status` l'affiche, sans port. Ce build autorise le \
            clair vers le tailnet déclaré, donc `http://` fonctionne. Sans \
            protocole, `http://` est supposé.
            """,
          avertissement: refus)
      }
      return ConseilAdresse(
        exemple: "https://mac-mini.mon-tailnet.ts.net",
        aide: """
          Ce build ne porte aucune exception ATS : iOS refuse `http://` vers un \
          nom de domaine (`-1022`). Deux voies — publier en HTTPS \
          (`tailscale serve --https 443`) et saisir une adresse `https://…`, ce \
          qui ne demande aucune exception ; ou reconstruire avec \
          `Scripts/construire-app-ios.sh`, qui pose l'exception pour votre \
          tailnet. Sans protocole, `http://` est supposé — et refusé ici.
          """,
        avertissement: refus)
    }
  }

  /// Le paquet courant porte-t-il une exception de clair, quelle qu'elle soit ?
  ///
  /// La question est volontairement large : le conseil générique n'a pas à
  /// savoir QUEL hôte sera saisi. Le cas précis — une adresse dont le domaine
  /// n'est pas couvert — est traité par l'avertissement, qui, lui, est exact.
  static func porteUneException(_ plist: [String: Any]?) -> Bool {
    ExceptionATS.autoriseTout(plist)
      || ExceptionATS.declarations(plist).contains { $0.autoriseLeClair }
  }

  /// Le texte affiché quand l'adresse saisie ne peut pas aboutir dans ce paquet.
  static func avertissement(
    adresse: String, plist: [String: Any]?, plateforme: Plateforme
  ) -> String? {
    guard ExceptionATS.seraRefuse(adresse, plist) else { return nil }
    if plateforme == .mac {
      // MESURÉ : lancé NU (binaire SwiftPM, sans Info.plist), le même code joint
      // le tailnet en clair — ATS ne s'y applique pas. L'avertissement est donc
      // réservé aux applications empaquetées, sinon il accuserait à tort un
      // outil de développement qui, lui, fonctionne.
      guard ExceptionATS.sousATS else { return nil }
      return """
        Le clair vers ce nom sera refusé : cette application n'a pas d'exception \
        ATS (`-1022`). Publiez en HTTPS (`tailscale serve --https 443`) et \
        saisissez une adresse `https://…`, ou réempaquetez avec \
        `Scripts/empaqueter-app-macos.sh`, qui pose l'exception.
        """
    }
    return """
      Le clair vers ce nom sera refusé : cette application n'a pas d'exception \
      ATS (`-1022`). Publiez en HTTPS (`tailscale serve --https 443`) et \
      saisissez une adresse `https://…`, ou reconstruisez avec \
      `Scripts/construire-app-ios.sh`, qui pose l'exception.
      """
  }
}
