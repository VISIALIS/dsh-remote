import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// LA CONFIGURATION RÉSEAU, PARTAGÉE PAR TOUS LES CLIENTS.
///
/// POURQUOI CE FICHIER EXISTE. `RemoteClient` et `FluxSession` construisaient
/// chacun la leur, et elles avaient DIVERGÉ : le client HTTP portait
/// `waitsForConnectivity` et des délais mesurés — c'est lui qui a corrigé le
/// `-1001` du réveil radio de l'iPhone (trois `ping` tailnet mesurés à 6 ms,
/// 412 ms, 6 ms) —, tandis que le flux, qui est pourtant la connexion la plus
/// longue à vivre et la plus exposée aux bascules Wi-Fi ↔ cellulaire, n'avait ni
/// l'un ni l'autre. Deux endroits pour une même décision finissent par en dire
/// deux choses : la décision vit donc ici, et les deux clients la lisent.
///
/// CE QUI EST COMMUN, ET POURQUOI. Une session ÉPHÉMÈRE, sans cache ni cookie :
/// un journal de session n'a rien à faire sur disque, et une réponse périmée
/// induirait l'utilisateur en erreur.
///
/// CE QUI DIFFÈRE, ET C'EST LE CŒUR DU SUJET. Une requête HTTP a une PATIENCE :
/// la liste des sessions prend 4 secondes à froid, la question de santé doit
/// échouer en cinq. Un flux n'a pas de patience de ce genre — il vit. La
/// confusion des deux se paie de deux façons, toutes deux mesurées, et chacune
/// est décrite à l'endroit où elle se produirait (`pourRequetes`, `pourFlux`).
public enum ConfigurationReseau {

  /// La patience d'une poignée de main WebSocket, en secondes.
  ///
  /// Vingt secondes : c'est le délai par défaut des requêtes de `RemoteClient`.
  /// La poignée de main traverse `tailscale serve` et répond en millisecondes
  /// sur un tailnet réveillé ; ce délai n'est là que pour ne pas attendre une
  /// machine muette plus longtemps que nécessaire.
  public static let delaiPoigneeDeMainFlux: TimeInterval = 20

  /// Une session éphémère, sans cache ni cookie — la base des deux autres.
  ///
  /// `ephemeral` ne suffit pas à lui seul : la politique de cache et les cookies
  /// sont posés explicitement, parce que c'est ce que le dépôt a décidé pour des
  /// données de session, et qu'un défaut de plateforme ne doit pas pouvoir en
  /// décider à notre place.
  ///
  /// `waitsForConnectivity` N'EST PAS ICI, et c'est délibéré : il appartient aux
  /// REQUÊTES (voir `pourRequetes`), pas au flux (voir `pourFlux`).
  private static func ephemere() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    config.urlCache = nil
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    return config
  }

  /// La configuration d'un client HTTP, avec SA patience.
  ///
  /// `waitsForConnectivity` VIT ICI, ET C'EST UNE MESURE. Trois `ping` tailnet
  /// vers l'iPhone donnent 6 ms, 412 ms, 6 ms : la radio s'endort entre deux
  /// échanges, et la première requête qui suit le réveil échouait en `-1001`. Ce
  /// drapeau fait patienter `URLSession` jusqu'au retour du chemin réseau, dans
  /// la limite des délais ci-dessous — il ne desserre aucun contrôle de sécurité,
  /// l'en-tête `Authorization` et l'absence d'`Origin` ne changent pas.
  ///
  /// `timeoutIntervalForResource` vaut au moins deux minutes : c'est la borne
  /// d'une requête qui a le droit d'être lente, et c'est elle qui empêche
  /// justement l'attente de durer indéfiniment.
  public static func pourRequetes(delai: TimeInterval) -> URLSessionConfiguration {
    let config = ephemere()
    config.waitsForConnectivity = true
    config.timeoutIntervalForRequest = delai
    config.timeoutIntervalForResource = max(delai, 120)
    return config
  }

  /// La configuration du flux WebSocket.
  ///
  /// POURQUOI ELLE N'EST PAS CELLE DES REQUÊTES — DEUX MESURES, DEUX PIÈGES.
  ///
  /// 1. **`timeoutIntervalForResource` borne la DURÉE TOTALE d'une tâche.** Un
  ///    flux « aligné » sur le client HTTP, avec `max(delai, 120)`, serait COUPÉ
  ///    toutes les deux minutes : un direct qui se rompt en boucle, avec une
  ///    reconnexion à chaque fois pour seule trace. Le délai de ressource du flux
  ///    reste donc celui de la plateforme (sept jours), et cette ligne existe pour
  ///    que personne ne « corrige » la dissymétrie en croyant à un oubli.
  ///
  /// 2. **`waitsForConnectivity` NE VA PAS ICI, ET C'EST UNE MESURE.** Recopier
  ///    le drapeau des requêtes a été essayé : sur une adresse qui refuse la
  ///    connexion, l'attente NE RENDAIT PAS LA MAIN. Constaté en éprouvant le
  ///    client — `FluxSession` vers `http://127.0.0.1:1` : le test a été tué
  ///    après **90 secondes**, alors que le même test passait en quelques
  ///    millisecondes avant. Avec un délai de ressource de sept jours, il ne se
  ///    serait pas terminé. Le mécanisme est cohérent : sur un flux, l'attente de
  ///    connectivité du système se substitue au lieu de rendre l'échec, et RIEN ne
  ///    vient la borner — la patience d'une requête, elle, a `max(delai, 120)`.
  ///
  ///    Ce que le flux a, à la place, est MEILLEUR : un échec rapide et la
  ///    politique de reconnexion du modèle (`Reconnexion` : 1 s, ×2, plafond 30 s,
  ///    quota de 20 tentatives). Un échec dit, et réessayé, vaut mieux qu'une
  ///    attente muette qui laisse l'écran sur « En direct ».
  ///
  /// `timeoutIntervalForRequest` ne borne ici QUE la poignée de main HTTP de
  /// l'upgrade : une fois la socket ouverte, `receive()` attend sans limite — et
  /// c'est bien ce qu'on veut d'un direct. La détection d'une socket MORTE ne
  /// dépend donc pas de ce délai : elle dépend du battement de cœur applicatif
  /// (voir `FluxSession`).
  public static func pourFlux() -> URLSessionConfiguration {
    let config = ephemere()
    config.timeoutIntervalForRequest = delaiPoigneeDeMainFlux
    return config
  }
}
