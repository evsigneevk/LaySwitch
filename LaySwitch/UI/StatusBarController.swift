import AppKit

/// Owns the menu bar status item and its dropdown menu.
/// The menu is rebuilt fresh each time it opens so that the
/// "Launch at Login" state is always current.
@MainActor
final class StatusBarController: NSObject {

    private let statusItem: NSStatusItem
    private let loginItemManager: LoginItemManager

    init(loginItemManager: LoginItemManager) {
        self.loginItemManager = loginItemManager

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        super.init()

        if let button = statusItem.button {
            // Use "LS" text as the menu bar icon instead of an SF Symbol.
            button.image = nil
            button.title = "LS"
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {

    /// Called just before the menu is shown — rebuild contents so state is fresh.
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        buildMenu(into: menu)
    }

    // MARK: - Private

    private func buildMenu(into menu: NSMenu) {
        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: ""
        )
        loginItem.target = self

        loginItem.state = loginItemManager.isEnabled ? .on : .off

        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit LaySwitch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    @objc private func toggleLoginItem() {
        do {
            try loginItemManager.toggle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not update Login Item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
