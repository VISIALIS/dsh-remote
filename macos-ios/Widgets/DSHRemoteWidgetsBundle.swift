import WidgetKit
import SwiftUI

struct DSHRemoteWidgetsBundle: WidgetBundle {
  var body: some Widget {
    DSHRemoteWidget()
    #if canImport(ActivityKit) && os(iOS)
    ActiviteSessionWidget()
    #endif
  }
}

// Point d'entrée de l'extension pour les builds Xcode (iOS, App Store).
//
// `@main` génère la section `__swift5_entry` qu'App Store Connect exige
// (ITMS-90896 sans elle). Le paquet macOS assemblé à la main par
// `Scripts/empaqueter-app-macos.sh` passe par `main.swift` et le shim C
// `widget_entry.c` : il compile avec `-D DSH_WIDGET_SHIM` pour ne pas avoir
// deux points d'entrée.
#if !DSH_WIDGET_SHIM
@main
extension DSHRemoteWidgetsBundle {}
#endif
