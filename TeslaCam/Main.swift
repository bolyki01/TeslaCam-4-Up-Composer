import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private let state = AppState()

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMainMenu()

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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    state.shutdownForTermination()
    if sender.modalWindow != nil {
      sender.abortModal()
    }
    return .terminateNow
  }

  func applicationWillTerminate(_ notification: Notification) {
    state.shutdownForTermination()
  }

  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    let urls = filenames.map { URL(fileURLWithPath: $0) }
    if !urls.isEmpty {
      state.ingestDroppedURLs(urls)
      NSApp.activate(ignoringOtherApps: true)
      window?.makeKeyAndOrderFront(nil)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  private func installMainMenu() {
    let appName = ProcessInfo.processInfo.processName
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let appMenu = NSMenu(title: appName)
    appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    NSApp.mainMenu = mainMenu
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
