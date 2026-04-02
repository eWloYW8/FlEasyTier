import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillFinishLaunching(_ notification: Notification) {
    // The privileged helper reuses the same binary. Hide it from the Dock
    // and menu bar so it runs as a pure background process.
    if ProcessInfo.processInfo.arguments.contains("--privileged-helper") {
      NSApp.setActivationPolicy(.prohibited)
      // Hide the XIB-defined window that would otherwise appear as a black frame.
      for window in NSApp.windows {
        window.orderOut(nil)
      }
    }
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        if !window.isVisible {
          window.makeKeyAndOrderFront(self)
        }
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
