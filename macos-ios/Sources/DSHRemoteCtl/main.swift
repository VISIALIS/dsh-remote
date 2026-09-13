import DSHRemoteKit
import Foundation

// `dsh-remote-ctl` — tool de validation du transport DSH Remote.
//
// Il existe pour PROUVER, en ligne de commande et sans interface, que le plugin
// hôte est joignable et que le protocole se décode. Tant que ce tool n'affiche
// pas les bonnes données, écrire du SwiftUI serait construire sur du sable.
//
// Le jeton n'est JAMAIS affiché ni journalisé : il est lu dans l'environnement
// (`DSH_REMOTE_TOKEN`) ou, à défaut, dans le coffre du harness — le fichier
// `.credentials.yaml`, déjà restreint à l'utilisateur (0600). Le tool dit
// seulement s'il l'a trouvé, et sa longueur.

let arguments = CommandLine.arguments

func echouer(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data(("erreur : " + message + "\n").utf8))
  exit(code)
}

func lireJeton() -> String? {
  if let direct = ProcessInfo.processInfo.environment["DSH_REMOTE_TOKEN"], !direct.isEmpty {
    return direct
  }
  let chemin = ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dsh")
  let coffre = chemin.appendingPathComponent(".credentials.yaml")
  guard let contenu = try? String(contentsOf: coffre, encoding: .utf8) else { return nil }
  // On cible l'enregistrement du plugin : le coffre contient AUSSI le secret de
  // signature des cookies du navigateur, de la meme longueur et du meme
  // alphabet. Prendre la premiere ligne « token » ramassait souvent ce secret,
  // qui n'est pas un jeton porteur et se fait refuser en 401.
  var dansLeBonEnregistrement = false
  for ligne in contenu.split(separator: "\n", omittingEmptySubsequences: false) {
    let texte = ligne.trimmingCharacters(in: .whitespaces)
    if texte.hasPrefix("dsh-remote/") || texte.hasPrefix("records/dsh-remote/") {
      dansLeBonEnregistrement = true
      continue
    }
    if texte.hasSuffix(":") && !texte.hasPrefix("token") && !texte.hasPrefix("payload") {
      if dansLeBonEnregistrement && !texte.contains("device-token") { dansLeBonEnregistrement = false }
    }
    guard dansLeBonEnregistrement, texte.hasPrefix("token:") else { continue }
    let valeur = texte.dropFirst("token:".count).trimmingCharacters(in: .whitespaces)
    if valeur.count >= 20 { return valeur }
  }
  return nil
}

func aider() {
  print(
    """
    dsh-remote-ctl — validation du transport DSH Remote

    USAGE
      dsh-remote-ctl <adresse> sante
      dsh-remote-ctl <adresse> sessions [limite]
      dsh-remote-ctl <adresse> serveurs
      dsh-remote-ctl <adresse> espaces
      dsh-remote-ctl <adresse> journal <identifiant> [limite]
      dsh-remote-ctl <adresse> prompt <identifiant> <texte> [queue|steer]
      dsh-remote-ctl <adresse> annuler <identifiant>
      dsh-remote-ctl <adresse> flux <identifiant> [secondes]
      dsh-remote-ctl serveurs

    ARGUMENTS
      <adresse>   http://127.0.0.1:3080 ou le nom MagicDNS du tailnet

    « serveurs » sans adresse interroge le Tailscale LOCAL (macOS) ;
    « <adresse> serveurs » demande la liste à l'HÔTE, ce qui est la seule voie
    possible depuis un iPhone.

    ÉCRITURE
      « prompt » adresse un message à une session — froide ou vivante, l'hôte
      la reprend au besoin. L'identifiant d'envoi est tiré ici : rejouer la
      commande crée un NOUVEAU message, comme le ferait l'interface.
      « annuler » interrompt le tour en cours et CONSERVE la file d'attente.

    JETON
      Lu dans DSH_REMOTE_TOKEN, sinon dans ~/.dsh/.credentials.yaml.
      Jamais affiché.
    """)
}

let adresse = arguments.count > 1 ? arguments[1] : ""
let commande = arguments.count > 2 ? arguments[2] : ""

// `serveurs` ne demande ni adresse ni jeton : il interroge Tailscale.
if adresse == "serveurs" {
  let machines = DecouverteServeurs.machinesDuTailnet()
  if machines.isEmpty {
    print("aucune machine decouverte")
    if let raison = DecouverteServeurs.diagnostic { print("raison : \(raison)") }
    exit(0)
  }
  print("Machines sur le tailnet : \(machines.count)\n")
  for machine in machines {
    let etat = machine.enLigne ? "en ligne   " : "hors ligne "
    print("  \(etat) \(machine.nom)")
    print("             \(machine.adresse)")
  }
  exit(0)
}

if adresse.isEmpty || adresse == "--help" || adresse == "-h" {
  aider()
  exit(adresse.isEmpty ? 1 : 0)
}

guard let jeton = lireJeton() else {
  echouer("aucun jeton d'appareil trouvé (DSH_REMOTE_TOKEN ou ~/.dsh/.credentials.yaml)")
}

let client: RemoteClient
do {
  client = try RemoteClient(adresse: adresse, jeton: jeton)
} catch {
  echouer(String(describing: error))
}

func horodatage(_ millisecondes: Int?) -> String {
  guard let millisecondes else { return "—" }
  let date = Date(timeIntervalSince1970: Double(millisecondes) / 1000)
  let formateur = DateFormatter()
  formateur.dateFormat = "dd/MM HH:mm"
  return formateur.string(from: date)
}

func octetsLisibles(_ octets: Int?) -> String {
  guard let octets else { return "—" }
  if octets < 1024 { return "\(octets) o" }
  if octets < 1024 * 1024 { return String(format: "%.0f Ko", Double(octets) / 1024) }
  return String(format: "%.1f Mo", Double(octets) / (1024 * 1024))
}

do {
  switch commande {
  case "sante":
    let sante = try await client.verifierSante()
    print("protocole    : \(sante.protocole)")
    print("service      : \(sante.nom ?? "—")")
    print("hôte         : \(sante.hote ?? "—")")
    print("accès        : \(sante.acces ?? "—")")
    print("version DSH  : \(sante.versionDsh ?? "—")")
    print(
      "capacités    : sessions=\(sante.capacites.sessions) journal=\(sante.capacites.journal) flux=\(sante.capacites.flux) écriture=\(sante.capacites.ecriture) annulation=\(sante.capacites.annulation.map(String.init) ?? "inconnu") découverte=\(sante.capacites.decouverte.map(String.init) ?? "inconnu")"
    )

  case "sessions":
    let limite = arguments.count > 3 ? Int(arguments[3]) : nil
    let liste = try await client.listerSessions(limite: limite)
    print("total : \(liste.total ?? liste.sessions.count) session(s)\n")
    for session in liste.sessions {
      let vivante = (session.vivante ?? false) ? "●" : "○"
      let titre = String(session.titreAffiche.prefix(46))
      let evenements = session.resume.nbEnregistrements ?? 0
      print("\(vivante) \(session.id.prefix(30))  \(titre.padding(toLength: 46, withPad: " ", startingAt: 0))  \(evenements) évts  \(octetsLisibles(session.octets))  \(horodatage(session.resume.dernierEvenementLe))")
    }

  case "espaces":
    let liste = try await client.listerEspaces()
    print("Espaces de travail publiés par l'hôte : \(liste.espaces.count)\n")
    for espace in liste.espaces {
      // « aucune session » est un état à part entière : un dossier enregistré
      // que l'interface web affiche, et que l'application ne pouvait pas montrer
      // tant qu'elle déduisait ses espaces des sessions.
      let etat = espace.sessions.isEmpty ? "aucune session" : "\(espace.sessions.count) session(s)"
      print("  \(etat.padding(toLength: 15, withPad: " ", startingAt: 0)) \(espace.chemin)")
    }

  case "serveurs":
    let liste = try await client.listerServeurs()
    if liste.serveurs.isEmpty {
      print("aucun Mac publié par cet hôte")
      if let raison = liste.diagnostic { print("raison : \(raison)") }
      exit(0)
    }
    print("Macs publiés par l'hôte : \(liste.serveurs.count)\n")
    for mac in liste.serveurs {
      let etat = mac.enLigne ? "en ligne   " : "hors ligne "
      let marque = mac.estLocal ? "  (hôte interrogé)" : ""
      print("  \(etat) \(mac.nom)\(marque)")
      print("             \(mac.adresse)")
    }

  case "journal":
    guard arguments.count > 3 else { echouer("identifiant de session manquant") }
    let identifiant = arguments[3]
    let limite = arguments.count > 4 ? Int(arguments[4]) : 20
    let journal = try await client.lireSession(identifiant, demande: DemandeJournal(depuis: 0, limite: limite))
    print("titre    : \(journal.session.titre ?? "—")")
    print("cwd      : \(journal.session.cwd ?? "—")")
    print("preset   : \(journal.session.preset ?? "—")")
    print("total    : \(journal.total ?? 0) enregistrement(s), page de \(journal.enregistrements.count)\n")
    for enregistrement in journal.enregistrements {
      print("  seq \(enregistrement.seq.map(String.init) ?? "—")  \(enregistrement.type ?? "?")")
    }

  case "prompt":
    guard arguments.count > 4 else { echouer("identifiant de session ou texte manquant") }
    let identifiant = arguments[3]
    let texte = arguments[4]
    let mode = arguments.count > 5 ? (ModePrompt(rawValue: arguments[5]) ?? .queue) : .queue
    let demande = DemandePrompt(texte: texte, mode: mode, requestId: DemandePrompt.identifiantNeuf())
    let reponse = try await client.envoyerPrompt(identifiant, demande: demande)
    print("accepté   : \(reponse.accepte)")
    print("mode      : \(reponse.mode ?? "—")")
    print("envoi     : \(reponse.requestId ?? "—")")
    print("reprise   : \(reponse.reprise.map { $0 ? "oui — la session était froide" : "non" } ?? "—")")

  case "annuler":
    guard arguments.count > 3 else { echouer("identifiant de session manquant") }
    let reponse = try await client.annuler(arguments[3])
    print("annulé    : \(reponse.annule)")

  case "flux":
    guard arguments.count > 3 else { echouer("identifiant de session manquant") }
    let identifiant = arguments[3]
    let duree = arguments.count > 4 ? (Double(arguments[4]) ?? 12) : 12
    guard let flux = FluxSession(adresse: adresse, jeton: jeton, identifiant: identifiant) else {
      echouer("adresse inutilisable pour un flux")
    }
    var bases = 0
    var evenements = 0
    var deltas = 0
    var sequences: [Int] = []
    print("flux ouvert sur \(identifiant), \(Int(duree)) s…")
    let expiration = Task {
      try? await Task.sleep(nanoseconds: UInt64(duree * 1_000_000_000))
      await flux.fermer()
    }
    for await message in await flux.messages() {
      switch message {
      case let .base(session, enregistrements, dernierSeq):
        bases += 1
        sequences.append(contentsOf: enregistrements.compactMap(\.seq))
        print("  base : « \(session.titre ?? "sans titre") » — \(enregistrements.count) enregistrement(s), dernierSeq=\(dernierSeq.map(String.init) ?? "—")")
      case let .evenement(enregistrement):
        evenements += 1
        if let seq = enregistrement.seq { sequences.append(seq) }
        print("  évènement seq=\(enregistrement.seq.map(String.init) ?? "—") \(enregistrement.type ?? "?")")
      case let .delta(dernierSeq):
        deltas += 1
        print("  delta, dernierSeq=\(dernierSeq.map(String.init) ?? "—")")
      case let .tronque(message):
        print("  TRONQUÉ : \(message)")
      case let .erreur(message):
        print("  ERREUR : \(message)")
      }
    }
    expiration.cancel()
    let connue = await flux.sequenceConnue
    let doublons = sequences.count - Set(sequences).count
    print("\nbase=\(bases) évènements=\(evenements) deltas=\(deltas)")
    print("seq reçus=\(sequences.count) distincts=\(Set(sequences).count) doublons=\(doublons)")
    print("curseur de reprise conservé : \(connue.map(String.init) ?? "—")")

  default:
    aider()
    echouer("commande inconnue : « \(commande) »")
  }
} catch {
  echouer(String(describing: error))
}
