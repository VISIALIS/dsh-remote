#if os(iOS)
  import SwiftUI
  import Vision
  import VisionKit

  /// SCANNER UN QR D'APPAIRAGE — la caméra, et rien de plus.
  ///
  /// POURQUOI `DataScannerViewController` ET PAS UNE CAMÉRA ÉCRITE À LA MAIN. Le
  /// cadrage, la mise au point, le suivi de l'item et le retour visuel sont
  /// fournis par le système, sans une ligne de `AVCaptureSession` à maintenir —
  /// et sans dépendance (RÈGLE #0).
  ///
  /// CE QUE CETTE VUE NE FAIT PAS : elle ne décode RIEN. Elle rend le texte lu,
  /// brut, et c'est `ModeleApp.appliquerAppairage` qui l'analyse — le contrat est
  /// éprouvé par le fixture partagé, pas par une seconde analyse écrite ici, qui
  /// aurait fini par diverger.
  ///
  /// ELLE NE S'OUVRE PAS PARTOUT, ET LE DIT. Un simulateur n'a pas de caméra, et
  /// un appareil sans puce Neural Engine ne sait pas faire tourner le scanner de
  /// VisionKit : dans les deux cas on l'annonce et on renvoie au collage du texte,
  /// qui reste le chemin de secours universel — c'est aussi celui du Mac.
  struct VueScanAppairage: View {
    /// Appelé avec le texte lu. La vue se ferme d'elle-même ensuite.
    var surLecture: (String) -> Void

    @Environment(\.dismiss) private var fermer

    /// La disponibilité est une MESURE, pas une supposition : elle est faite une
    /// fois, à l'apparition, et elle décide de ce qu'on montre.
    @State private var disponible: Bool?
    @State private var lectureFaite = false

    var body: some View {
      NavigationStack {
        Group {
          if disponible == false {
            messageIndisponible
          } else {
            CaméraQR { texte in
              // UNE SEULE LECTURE PAR OUVERTURE. Le délégué rappelle à chaque
              // image qui contient encore le code : sans ce verrou, un scan
              // appliquerait dix fois le même appairage, et dix connexions
              // partiraient.
              guard !lectureFaite else { return }
              lectureFaite = true
              surLecture(texte)
              fermer()
            }
            .ignoresSafeArea(edges: .bottom)
          }
        }
        .navigationTitle(T("Scanner le QR code"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(L("Annuler")) { fermer() }
          }
        }
        .task {
          if disponible == nil {
            disponible = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
          }
        }
      }
    }

    private var messageIndisponible: some View {
      ContentUnavailableView {
        Label { T("Caméra indisponible") } icon: { Image(systemName: "camera.fill") }
      } description: {
        T("Ce simulateur n'a pas de caméra, ou ce modèle ne sait pas analyser un QR code en direct. Utilisez « Coller un appairage » : le texte affiché sous le QR code du panneau fait exactement la même chose.")
      }
    }
  }

  /// L'ENVELOPPE UIKit DU SCANNER, isolée pour que la vue SwiftUI ci-dessus reste
  /// lisible et pour que l'indisponibilité se teste sans caméra.
  private struct CaméraQR: UIViewControllerRepresentable {
    var surLecture: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
      let controleur = DataScannerViewController(
        recognizedDataTypes: [.barcode(symbologies: [.qr])],
        qualityLevel: .balanced,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: false,
        isHighlightingEnabled: true
      )
      controleur.delegate = context.coordinator
      return controleur
    }

    func updateUIViewController(_ controleur: DataScannerViewController, context: Context) {
      // `startScanning` LÈVE quand la caméra n'est pas autorisée ou déjà prise :
      // on ne veut pas d'une exception qui emporterait la vue, donc on l'absorbe
      // et l'écran reste sur le retour visuel du système.
      try? controleur.startScanning()
    }

    func makeCoordinator() -> Coordinateur {
      Coordinateur(surLecture: surLecture)
    }

    final class Coordinateur: NSObject, DataScannerViewControllerDelegate {
      private let surLecture: (String) -> Void

      init(surLecture: @escaping (String) -> Void) {
        self.surLecture = surLecture
      }

      func dataScanner(
        _ scanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
      ) {
        for item in addedItems {
          guard case let .barcode(code) = item else { continue }
          guard let charge = code.payloadStringValue, !charge.isEmpty else { continue }
          surLecture(charge)
          return
        }
      }
    }
  }
#endif
