import Foundation
import Testing

@testable import DSHRemoteKit

// La découverte par l'HÔTE : « le Mac découvre, l'iPhone consomme ».
//
// C'est la seule voie praticable depuis un iPhone, qui ne peut pas exécuter de
// processus. Les charges utiles ci-dessous sont des copies de réponses RÉELLES
// du plugin (`GET /dsh-remote/v1/serveurs`), avec les noms de machines et de
// tailnet remplacés par des valeurs d'exemple — le dépôt n'accueille aucun
// identifiant de machine réelle.

private func reponseHote(_ json: String) -> ListeServeurs {
  try! JSONDecoder().decode(ListeServeurs.self, from: Data(json.utf8))
}

@Test("La liste publiée par l'hôte se décode, et l'hôte interrogé est marqué")
func listeDeLHote() throws {
  let liste = reponseHote(
    """
    {
      "protocole": 1,
      "serveurs": [
        { "nom": "Portable Un", "nomDNS": "portable-un.exemple.ts.net", "enLigne": true, "local": true },
        { "nom": "Bureau Mini", "nomDNS": "bureau-mini.exemple.ts.net", "enLigne": true, "local": false },
        { "nom": "Portable Deux", "nomDNS": "portable-deux.exemple.ts.net", "enLigne": false, "local": false }
      ],
      "diagnostic": null
    }
    """)

  #expect(liste.serveurs.count == 3)
  #expect(liste.diagnostic == nil)

  // L'ordre de l'hôte est conservé tel quel : c'est lui qui sait ce qui est en
  // ligne, le client n'a pas à le recalculer.
  #expect(liste.serveurs.map(\.nom) == ["Portable Un", "Bureau Mini", "Portable Deux"])

  // Seul l'hôte qui a répondu est marqué : sur iPhone, ce n'est PAS l'appareil.
  #expect(liste.serveurs.filter(\.estLocal).map(\.nom) == ["Portable Un"])

  // L'adresse se déduit du nom DNS, et reste utilisable telle quelle.
  #expect(try #require(liste.serveurs.first).adresse == "http://portable-un.exemple.ts.net")
}

@Test("Une liste vide de l'hôte porte sa raison, et ce n'est pas une erreur")
func listeVideAvecRaison() throws {
  let liste = reponseHote(
    """
    { "protocole": 1, "serveurs": [], "diagnostic": "tailscale muet: delai depasse" }
    """)

  #expect(liste.serveurs.isEmpty)
  // Sans cette raison, le client ne pourrait pas distinguer un tailnet vide d'un
  // Tailscale arrêté sur l'hôte — deux causes aux corrections opposées.
  #expect(liste.diagnostic == "tailscale muet: delai depasse")
}

@Test("Un hôte qui ne publie pas « local » ne fait pas échouer toute la liste")
func champsFacultatifsAbsents() throws {
  // Le champ `local` est un détail d'AFFICHAGE : son absence ne doit pas vider
  // la liste, sinon un client plus récent qu'un hôte ancien n'afficherait plus
  // aucune machine. Seuls le nom et le nom DNS sont exigés.
  let liste = reponseHote(
    """
    { "protocole": 1, "serveurs": [ { "nom": "Bureau Mini", "nomDNS": "bureau-mini.exemple.ts.net" } ] }
    """)

  let serveur = try #require(liste.serveurs.first)
  #expect(serveur.nom == "Bureau Mini")
  #expect(serveur.estLocal == false)
  // Un serveur sans `enLigne` n'est pas annoncé en ligne à tort.
  #expect(serveur.enLigne == false)
}

@Test("Un hôte plus ancien n'annonce pas la découverte : « inconnu » n'est pas « oui »")
func capaciteDecouverteAbsente() throws {
  // La capacité est optionnelle À DESSEIN. Un hôte antérieur à cette route ne
  // renvoie pas le champ : le client doit alors garder la saisie manuelle, au
  // lieu d'attendre une liste qui ne viendra jamais.
  let sante = try JSONDecoder().decode(
    Sante.self,
    from: Data(
      """
      { "protocole": 1, "capacites": { "sessions": true, "journal": true, "flux": true, "ecriture": false, "approbations": false } }
      """.utf8))

  #expect(sante.capacites.decouverte == nil)
  #expect(sante.capacites.sessions == true)
}

@MainActor
@Test("La légende dit qu'une machine est l'hôte interrogé, sans la confondre avec l'appareil")
func legendeDeLHote() {
  let modele = modeleDeTest()
  let hote = ServeurMac(nom: "Portable Un", nomDNS: "portable-un.exemple.ts.net", enLigne: true, estLocal: true)
  let autre = ServeurMac(nom: "Bureau Mini", nomDNS: "bureau-mini.exemple.ts.net", enLigne: false)

  #expect(modele.legendeServeur(hote) == "hôte interrogé · en ligne")
  #expect(modele.legendeServeur(autre) == "hors ligne")
}
