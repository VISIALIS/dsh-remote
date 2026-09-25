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
