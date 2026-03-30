import AppKit
import OSLog

private let log = Logger(subsystem: "com.layswitch.app", category: "FocusMonitor")

/// Monitors application focus changes to save and restore keyboard layouts.
///
/// On every app switch:
/// 1. **Save** — when an app loses focus, the current input source is stored for it.
/// 2. **Restore** — when an app gains focus, its saved layout is applied after a
///    short delay so that any Space-transition animations fully settle before the
///    layout is switched. If the user leaves before the delay elapses, the restore
///    is cancelled and no layout is saved for that brief visit.
@MainActor
final class AppFocusMonitor {

    private let inputSourceManager: any InputSourceManaging
    private let layoutStore: any LayoutStoring

    /// How long to wait after activation before restoring the saved layout.
    /// Default 100 ms
    private let restoreDelay: TimeInterval

    private var activationObserver: NSObjectProtocol?
    private var deactivationObserver: NSObjectProtocol?

    /// Pending restore. Cancelled if the user switches away before it fires.
    private var restoreWorkItem: DispatchWorkItem?

    /// Bundle ID for which a restore is currently queued.
    private var pendingRestoreBundleID: String?

    init(
        inputSourceManager: some InputSourceManaging,
        layoutStore: some LayoutStoring,
        restoreDelay: TimeInterval = 0.1
    ) {
        self.inputSourceManager = inputSourceManager
        self.layoutStore = layoutStore
        self.restoreDelay = restoreDelay
    }

    // MARK: - Lifecycle

    func start() {
        let initial = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        log.info("Started. Frontmost: \(initial ?? "nil", privacy: .public)")

        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleDeactivation(app) }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated { self?.handleActivation(app) }
        }
    }

    func stop() {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        pendingRestoreBundleID = nil

        if let o = deactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        if let o = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        deactivationObserver = nil
        activationObserver = nil
    }

    // MARK: - Private

    /// App lost focus — save its current layout.
    private func handleDeactivation(_ app: NSRunningApplication?) {
        guard
            let bundleID = app?.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return }

        // User left before the restore timer fired — cancel it and skip saving.
        // The stored layout from the previous full session is still correct.
        if pendingRestoreBundleID == bundleID {
            restoreWorkItem?.cancel()
            restoreWorkItem = nil
            pendingRestoreBundleID = nil
            log.debug("← \(bundleID, privacy: .public) — left before restore fired, save skipped")
            return
        }

        guard let currentID = inputSourceManager.currentSourceID() else { return }
        log.info("← \(bundleID, privacy: .public) — saving: \(currentID, privacy: .public)")
        layoutStore.setSourceID(currentID, forBundleID: bundleID)
    }

    /// App gained focus — schedule a layout restore after `restoreDelay`.
    private func handleActivation(_ app: NSRunningApplication?) {
        guard
            let bundleID = app?.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else { return }

        // Cancel any restore queued for a previous activation.
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        pendingRestoreBundleID = nil

        guard let savedID = layoutStore.sourceID(forBundleID: bundleID) else {
            log.info("→ \(bundleID, privacy: .public) — no saved layout")
            return
        }

        let delayMs = Int(restoreDelay * 1000)
        log.info("→ \(bundleID, privacy: .public) — will restore \(savedID, privacy: .public) in \(delayMs) ms")
        pendingRestoreBundleID = bundleID

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.restoreWorkItem = nil
                self.pendingRestoreBundleID = nil
                log.info("→ \(bundleID, privacy: .public) — restoring: \(savedID, privacy: .public)")
                self.inputSourceManager.selectSource(withID: savedID)
            }
        }
        restoreWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay, execute: work)
    }
}
