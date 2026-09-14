import AppKit
import SwiftUI

// MESURE ISOLÉE : que fait ÉCHAP sur un `confirmationDialog` SwiftUI dont
// l'action destructive est déclarée EN PREMIER ? On journalise chaque issue dans
// un fichier, parce qu'un écran ne dit pas QUI a agi.
let journal = URL(fileURLWithPath: ProcessInfo.processInfo.environment["JOURNAL"]
  ?? "/tmp/sonde-dialogue.txt")

func noter(_ ligne: String) {
  let texte = "\(Date().timeIntervalSince1970) \(ligne)\n"
  if let handle = try? FileHandle(forWritingTo: journal) {
    handle.seekToEndOfFile()
    handle.write(Data(texte.utf8))
    try? handle.close()
  } else {
    try? Data(texte.utf8).write(to: journal)
  }
}

enum Variante: String {
  case telleQuelle = "A-telle-quelle"
  case durcie = "B-durcie"
}
let variante = Variante(rawValue: ProcessInfo.processInfo.environment["VARIANTE"] ?? "A-telle-quelle")!

struct Contenu: View {
  @State private var ouverte = false

  var body: some View {
    VStack(spacing: 16) {
      Text("essai \(variante.rawValue)")
      Button("Reinitialiser l'application") { noter("bouton-presse"); ouverte = true }
        .confirmationDialog(
          "Reinitialiser l'application ?", isPresented: $ouverte, titleVisibility: .visible
        ) {
          Button("Tout effacer", role: .destructive) { noter("ISSUE=destructif") }
          if variante == .telleQuelle {
            Button("Annuler", role: .cancel) { noter("ISSUE=annule") }
          } else {
            Button("Annuler", role: .cancel) { noter("ISSUE=annule") }
              .keyboardShortcut(.cancelAction)
          }
        } message: {
          Text("Les jetons gardes sur cet appareil seront effaces.")
        }
      Button("Quitter") { noter("quitte"); NSApp.terminate(nil) }
    }
    .padding(40)
  }
}

final class Delegue: NSObject, NSApplicationDelegate {
  var fenetre: NSWindow?

  // LA FENÊTRE EST CRÉÉE ICI, PAS AVANT `run()` : une fenêtre construite avant
  // `finishLaunching` n'est jamais posée — mesuré : `count of windows` valait 0
  // et rien ne s'affichait.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    let f = NSWindow(
      contentRect: NSRect(x: 200, y: 480, width: 420, height: 220),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    f.title = "Essai dialogue \(variante.rawValue)"
    f.contentView = NSHostingView(rootView: Contenu())
    f.makeKeyAndOrderFront(nil)
    fenetre = f
    NSApp.activate(ignoringOtherApps: true)
    noter("lance")
  }
}

let delegue = Delegue()
let app = NSApplication.shared
app.delegate = delegue
app.run()
