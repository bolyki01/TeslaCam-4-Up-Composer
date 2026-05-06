#if os(iOS)
import SwiftUI
@main
struct TeslaCamIPadApp: App {
  @StateObject private var state = AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(state)
    }
  }
}
#endif
