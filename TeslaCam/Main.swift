import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private let state = AppState()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let content = ContentView().environmentObject(state)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "TeslaCam Pro"
    window.contentView = NSHostingView(rootView: content)
    window.makeKeyAndOrderFront(nil)

    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    self.window = window
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}

@main
struct MainApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.activate(ignoringOtherApps: true)
    app.run()
  }
}
