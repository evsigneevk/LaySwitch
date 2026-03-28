import AppKit
import Carbon.HIToolbox
import OSLog

private let log = Logger(subsystem: "com.layswitch.app", category: "FocusMonitor")

/// Monitors input source and application activation events.
///
/// Two complementary mechanisms keep the store up to date:
///
/// 1. `kTISNotifySelectedKeyboardInputSourceChanged` (DistributedNotificationCenter)
///    Fires immediately whenever the layout changes — including inside a full-screen
///    app on a separate Space, before any app-switch notification arrives.
///    This is the primary save path.
///
/// 2. `NSWorkspace.didActivateApplicationNotification`
///    Fires when the frontmost app changes. Used to restore the saved layout
///    for the newly active app.
///
/// Suppression strategy: after a programmatic restore we record the source ID
/// we set (`pendingRestoreID`). The next TIS notification is suppressed only if
/// the current layout still matches that value — meaning nothing else overrode
/// our change. If another app or macOS immediately changed the layout to a
/// different value, that notification is not suppressed and the new value is
/// saved as the app's preferred layout.
///
/// Space-transition race condition: during a trackpad swipe between Spaces,
/// macOS changes the input source in one of two orderings relative to the
/// activation notification:
///
/// A. TIS fires while `frontmostApplication` is still the SOURCE app, then
///    activation fires. The save is deferred by one run-loop pass so that
///    the activation notification changes `frontmostApplication` first; the
///    bundle-ID mismatch is detected and the save is discarded.
///
/// B. macOS updates `frontmostApplication` to the TARGET app before the
///    activation notification fires, then TIS fires. `confirmedFrontmostBundleID`
///    (updated only inside `handleActivation`) still points to the source app,
///    so the mismatch is detected and the save is discarded immediately.
@MainActor
final class AppFocusMonitor {

    private let inputSourceManager: any InputSourceManaging
    private let layoutStore: any LayoutStoring

    private var activationObserver: NSObjectProtocol?
    private var tisObserver: NSObjectProtocol?

    /// Source ID set by our last programmatic restore. Cleared after the first
    /// TIS notification that follows, whether suppressed or not.
    private var pendingRestoreID: String?

    /// Bundle ID of the last app confirmed via `didActivateApplicationNotification`.
    /// TIS notifications for a bundle ID that doesn't match this value are
    /// discarded — they arrived before the activation notification for that app,
    /// meaning macOS changed `frontmostApplication` during a Space-transition
    /// animation before we had a chance to restore the correct layout.
    private var confirmedFrontmostBundleID: String?

    init(
        inputSourceManager: some InputSourceManaging,
        layoutStore: some LayoutStoring
    ) {
        self.inputSourceManager = inputSourceManager
        self.layoutStore = layoutStore
    }

    // MARK: - Lifecycle

    func start() {
        confirmedFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let frontmost = confirmedFrontmostBundleID
        log.info("Started. Initial frontmost app: \(frontmost ?? "nil", privacy: .public)")

        // 1. Watch for layout changes — save immediately for the current app.
        tisObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleInputSourceChange()
            }
        }

        // 2. Watch for app switches — restore the saved layout for the new app.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleActivation(notification)
            }
        }
    }

    func stop() {
        if let o = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        if let o = tisObserver {
            DistributedNotificationCenter.default().removeObserver(o)
        }
        activationObserver = nil
        tisObserver = nil
    }

    // MARK: - Private

    /// Called whenever the active input source changes.
    /// Saves the new layout for the current frontmost app.
    private func handleInputSourceChange() {
        guard
            let currentID = inputSourceManager.currentSourceID(),
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            bundleID != Bundle.main.bundleIdentifier
        else {
            pendingRestoreID = nil
            return
        }

        // Consume the pending restore marker on the first TIS notification
        // after a restore, regardless of outcome.
        let pending = pendingRestoreID
        pendingRestoreID = nil

        // Suppress only if the layout matches what we just set ourselves.
        // If something else changed it to a different value, save that value.
        if let pending, currentID == pending {
            log.debug("Suppressed own restore notification (\(currentID, privacy: .public) in \(bundleID, privacy: .public))")
            return
        }

        // Case B guard: discard if macOS updated `frontmostApplication` to this app
        // before the activation notification fired (the app hasn't been confirmed yet).
        guard bundleID == confirmedFrontmostBundleID else {
            log.debug("Discarded early TIS save — activation not yet received for \(bundleID, privacy: .public)")
            return
        }

        // Case A guard: defer by one run-loop pass. If a Space-transition TIS fires
        // while `frontmostApplication` still shows the departing app, the activation
        // notification will update `frontmostApplication` before this block runs —
        // the bundle-ID mismatch causes the save to be discarded.
        let capturedID = currentID
        let capturedBundleID = bundleID
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == capturedBundleID else {
                    log.debug("Discarded stale TIS save — app changed before save committed (\(capturedBundleID, privacy: .public))")
                    return
                }
                self.layoutStore.setSourceID(capturedID, forBundleID: capturedBundleID)
            }
        }
    }

    /// Called when a different app becomes frontmost.
    /// Restores the saved layout for the newly active app.
    private func handleActivation(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            let newBundleID = app.bundleIdentifier
        else { return }

        if newBundleID == Bundle.main.bundleIdentifier {
            log.debug("Skipping self-activation")
            return
        }

        // Confirm the new frontmost app before restoring. Any TIS notification
        // that fired after macOS updated `frontmostApplication` but before this
        // point is now valid to process (Case B check above will pass).
        confirmedFrontmostBundleID = newBundleID

        if let savedID = layoutStore.sourceID(forBundleID: newBundleID) {
            log.info("→ \(newBundleID, privacy: .public) — restoring: \(savedID, privacy: .public)")
            pendingRestoreID = savedID
            inputSourceManager.selectSource(withID: savedID)
        } else {
            log.info("→ \(newBundleID, privacy: .public) — no saved layout, keeping current")
        }
    }
}
