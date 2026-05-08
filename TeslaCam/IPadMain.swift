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
    .commands {
      CommandMenu("Playback") {
        Button("Play/Pause") {
          state.togglePlay()
        }
        .keyboardShortcut(.space, modifiers: [])

        Button("Back 5s") {
          state.stepPlayback(by: -5)
        }
        .keyboardShortcut(.leftArrow, modifiers: [])

        Button("Forward 5s") {
          state.stepPlayback(by: 5)
        }
        .keyboardShortcut(.rightArrow, modifiers: [])

        Button("Next Event") {
          state.jumpToNextEvent(direction: 1)
        }
        .keyboardShortcut(.downArrow, modifiers: [])

        Button("Previous Event") {
          state.jumpToNextEvent(direction: -1)
        }
        .keyboardShortcut(.upArrow, modifiers: [])

        Button("Playback Speed") {
          state.cyclePlaybackRate()
        }
        .keyboardShortcut("]", modifiers: [])
      }
    }
  }
}
#endif
