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
      // ── Choix du serveur ───────────────────────────────────────────────────
      //
      // On choisit une MACHINE, pas une adresse. L'adresse en découle : personne
      // ne devrait avoir à taper un nom MagicDNS de 40 caractères pour dire
      // « le Mac mini ». Le champ d'adresse reste disponible plus bas pour les
      // cas que la découverte ne couvre pas.
      Section("Serveur") {
        if modele.serveurs.isEmpty {
          // Une liste vide DOIT s'expliquer. Sans ce texte, l'utilisateur croit
          // à une panne de l'application alors que la cause est presque
          // toujours l'absence de Tailscale ou une adresse à saisir.
          VStack(alignment: .leading, spacing: 8) {
            Label(DecouverteServeurs.messageDAbsence(), systemImage: "exclamationmark.triangle")
              .font(.callout)
              .foregroundStyle(.orange)
            HStack(spacing: 12) {
              Button("Rafraîchir") { modele.rafraichirServeurs() }
                .font(.caption)
              #if os(iOS)
                Button("Installer Tailscale") {
                  if let url = URL(string: "https://apps.apple.com/app/tailscale/id1470499037") {
                    UIApplication.shared.open(url)
                  }
                }
                .font(.caption)
              #endif
            }
          }
          .padding(.vertical, 4)
        } else {
          ForEach(modele.serveurs) { serveur in
            Button {
              Task { await modele.choisirEtConnecter(serveur) }
            } label: {
              HStack(spacing: 10) {
                Image(systemName: serveur.symbole)
                  .font(.title3)
                  .frame(width: 26)
                  .foregroundStyle(serveur.enLigne ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                  Text(serveur.nom).font(.body)
                  Text(serveur.enLigne ? "en ligne" : "hors ligne")
                    .font(.caption2)
                    .foregroundStyle(serveur.enLigne ? Color.green : Color.secondary)
                }
                Spacer()
                if modele.serveurChoisi == serveur {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
              }
            }
            .buttonStyle(.plain)
          }
          Button("Rafraîchir la liste") { modele.rafraichirServeurs() }
            .font(.caption)
        }
      }

      Section(modele.serveurs.isEmpty ? "Serveur" : "Adresse") {
        LabeledContent("Adresse") {
          TextField("http://127.0.0.1:3080", text: $modele.adresse)
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.URL)
            #endif
        }
        // Le champ du jeton est TOUJOURS visible.
        //
        // Il était auparavant conditionné par `!modele.jetonDisponible`, c'est-à-dire
        // caché dès qu'un jeton était présent. Le défaut : `jetonDisponible` devient
        // vrai dès le PREMIER caractère saisi, donc le champ disparaissait sous les
        // doigts de l'utilisateur, qui ne pouvait jamais terminer sa saisie. Un
        // formulaire dont un champ s'évapore à la frappe n'est pas un formulaire.
        //
        // Afficher aussi l'état permet de comprendre pourquoi « Se connecter »
        // fonctionne sans rien saisir sur le Mac.
        LabeledContent("Jeton") {
          HStack(spacing: 8) {
            SecureField(modele.jetonDisponible ? "déjà enregistré — saisir pour remplacer" : "jeton d'appareil", text: $modele.jetonSaisi)
              .textFieldStyle(.roundedBorder)
              #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
              #endif
            // 43 caractères en base64url : les coller est plus sûr que les taper.
            Button {
              modele.collerLeJeton()
            } label: {
              Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Coller le jeton depuis le presse-papier")
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
