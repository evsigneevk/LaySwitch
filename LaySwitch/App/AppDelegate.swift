import AppKit

@MainActor
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Entry point called by @main. Wires the delegate to the shared
    // NSApplication instance and starts the run loop.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var inputSourceManager: InputSourceManager!
    private var layoutStore: LayoutStore!
    private var loginItemManager: LoginItemManager!
    private var focusMonitor: AppFocusMonitor!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a background agent: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        inputSourceManager = InputSourceManager()
        layoutStore = LayoutStore()
        loginItemManager = LoginItemManager()

        focusMonitor = AppFocusMonitor(
            inputSourceManager: inputSourceManager,
            layoutStore: layoutStore
        )

        statusBarController = StatusBarController(
            loginItemManager: loginItemManager
        )

        // Start monitoring last — all dependencies are ready.
        focusMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusMonitor.stop()
    }
}
