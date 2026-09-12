import DSHRemoteKit
import SwiftUI

/// Fenêtre principale : la liste des sessions à gauche, le journal à droite.
///
/// `NavigationSplitView` est employé des deux côtés plutôt qu'une navigation par
/// pile : sur le Mac c'est une vraie vue en colonnes, et sur iPhone SwiftUI la
/// replie lui-même en pile. Une seule structure d'interface pour les deux
/// plateformes, donc un seul comportement à vérifier.
public struct VuePrincipale: View {
  @State private var modele = ModeleApp()
  @State private var sessionSelectionnee: SessionListee?

  public init() {}

  public var body: some View {
    NavigationSplitView {
      VueConnexion(modele: modele)
    } detail: {
      if let session = sessionSelectionnee {
        VueJournal(modele: modele, session: session)
      } else {
        ContentUnavailableView(
          "Aucune session ouverte",
          systemImage: "terminal",
          description: Text("Choisissez une session dans la liste pour lire son journal.")
        )
      }
    }
    .task {
      if modele.jetonSaisi.isEmpty, let local = ModeleApp.jetonLocal() {
        modele.enregistrerJeton(local)
      }
      await modele.connecter()
    }
  }
}

/// Colonne de gauche : connexion, état, puis liste des sessions.
struct VueConnexion: View {
  @Bindable var modele: ModeleApp
  @State private var selection: SessionListee?

  var body: some View {
    List(selection: $selection) {
      Section("Serveur") {
        LabeledContent("Adresse") {
          TextField("http://127.0.0.1:3080", text: $modele.adresse)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
            #endif
        }
        if !modele.jetonDisponible {
          LabeledContent("Jeton") {
            SecureField("jeton d'appareil", text: $modele.jetonSaisi)
              .textFieldStyle(.roundedBorder)
          }
        }
        HStack {
          Button("Se connecter") {
            Task { await modele.connecter() }
          }
          .disabled(modele.enChargement)
          if modele.enChargement { ProgressView().controlSize(.small) }
        }
      }

      if let erreur = modele.erreur {
        Section {
          Label(erreur, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
        }
      }

      Section {
        Toggle("Sessions vivantes seulement", isOn: $modele.filtresActifs)
      }

      Section("Sessions (\(modele.sessionsAffichees.count))") {
        ForEach(modele.sessionsAffichees, id: \.id) { session in
          LigneSession(session: session).tag(session)
        }
      }
    }
    .navigationTitle("DSH Remote")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .onChange(of: selection) { _, nouvelle in
      guard let nouvelle else { return }
      Task { await modele.ouvrir(nouvelle) }
    }
    .refreshable { await modele.rafraichir() }
  }
}

/// Une ligne de la liste : point d'état, titre, projet, volume et date.
struct LigneSession: View {
  let session: SessionListee

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Circle()
          .fill(session.vivante == true ? Color.green : Color.secondary.opacity(0.4))
          .frame(width: 7, height: 7)
        Text(session.titreAffiche)
          .lineLimit(1)
          .font(.body)
      }
      HStack(spacing: 8) {
        if let cwd = session.resume.cwd {
          Text((cwd as NSString).lastPathComponent)
            .lineLimit(1)
        }
        if let evenements = session.resume.nbEnregistrements {
          Text("\(evenements) évts")
        }
        if let octets = session.octets {
          Text(ByteCountFormatter.string(fromByteCount: Int64(octets), countStyle: .file))
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      if let illisible = session.illisible {
        Text(illisible).font(.caption2).foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 2)
  }
}
