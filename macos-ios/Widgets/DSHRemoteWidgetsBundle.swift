import WidgetKit
import SwiftUI

@main
struct DSHRemoteWidgetsBundle: WidgetBundle {
  var body: some Widget {
    DSHRemoteWidget()
    #if canImport(ActivityKit) && os(iOS)
    ActiviteSessionWidget()
    #endif
  }
}
