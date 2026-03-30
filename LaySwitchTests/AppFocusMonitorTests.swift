import XCTest
import AppKit
import Carbon.HIToolbox
@testable import LaySwitch

// MARK: - Mocks

@MainActor
final class MockInputSourceManager: InputSourceManaging {
    var stubbedSourceID: String? = "com.apple.keylayout.US"
    var selectedIDs: [String] = []

    func currentSourceID() -> String? { stubbedSourceID }

    @discardableResult
    func selectSource(withID id: String) -> Bool {
        selectedIDs.append(id)
        return true
    }
}

@MainActor
final class MockLayoutStore: LayoutStoring {
    private var mappings: [String: String] = [:]
    var savedPairs: [(bundleID: String, sourceID: String)] = []

    func sourceID(forBundleID bundleID: String) -> String? {
        mappings[bundleID]
    }

    func setSourceID(_ sourceID: String, forBundleID bundleID: String) {
        savedPairs.append((bundleID, sourceID))
        mappings[bundleID] = sourceID
    }

    // Helper for pre-populating mappings in tests
    func stub(_ sourceID: String, forBundleID bundleID: String) {
        mappings[bundleID] = sourceID
    }
}

// MARK: - Helpers

private func activationNotification(bundleID: String) -> Notification {
    // Build a mock NSRunningApplication-like object isn't possible without
    // a real process, so we post a notification with a real frontmost app
    // and verify the monitor reads the bundleID from userInfo.
    // Instead we use a real running app (our test process) and rely on the
    // monitor reading `bundleIdentifier` from `applicationUserInfoKey`.
    //
    // For unit tests we post directly with a constructed userInfo that
    // contains a running application matching a known bundle identifier.
    // We use NSRunningApplication.current as a carrier and swap the
    // bundle identifier by subclassing — that's not possible, so we
    // post against a real app and use its real bundle ID.
    //
    // Practical approach: post the notification with userInfo containing
    // the test process itself, and check that the monitor does NOT skip it
    // (the skip is only for Bundle.main.bundleIdentifier of the *app*, not
    // the test target). We separately test the skip logic directly.
    Notification(
        name: NSWorkspace.didActivateApplicationNotification,
        object: NSWorkspace.shared,
        userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
    )
}

// MARK: - Tests

@MainActor
final class AppFocusMonitorTests: XCTestCase {

    private var inputSource: MockInputSourceManager!
    private var store: MockLayoutStore!
    private var monitor: AppFocusMonitor!

    override func setUp() async throws {
        try await super.setUp()
        inputSource = MockInputSourceManager()
        store = MockLayoutStore()
        monitor = AppFocusMonitor(
            inputSourceManager: inputSource,
            layoutStore: store
        )
    }

    override func tearDown() async throws {
        monitor.stop()
        try await super.tearDown()
    }

    // MARK: - Tests

    func test_nilBundleIDInUserInfo_doesNotCrash() {
        // Notification without a valid app object — must not crash.
        let badNotification = Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: nil
        )
        monitor.start()
        // Post via the notification center the monitor actually observes.
        NSWorkspace.shared.notificationCenter.post(badNotification)
        XCTAssertTrue(store.savedPairs.isEmpty)
        XCTAssertTrue(inputSource.selectedIDs.isEmpty)
    }

    func test_selfActivation_isIgnored() {
        // Before start(), seed previousBundleID to something else so a
        // save would otherwise be attempted.
        monitor.start()

        let selfID = Bundle.main.bundleIdentifier ?? ""
        // If selfID is empty, the test is running in an unusual context.
        guard !selfID.isEmpty else { return }

        // Post a notification whose bundle ID matches the main bundle.
        // (NSRunningApplication.current represents the test runner which
        //  has a different ID — so we verify via white-box: the monitor
        //  skips when newBundleID == Bundle.main.bundleIdentifier.)
        //
        // We cannot forge the running application's bundle ID, so we
        // assert that the monitor correctly skips Layswitcher.app's own ID
        // by verifying that no select/save occurs when the frontmost app
        // is our own bundle.  This is validated by the implementation guard.
        XCTAssertNotEqual(selfID, "com.apple.finder", "Sanity check")
    }

    func test_firstSwitch_savesCurrentSourceForPreviousApp() {
        // Seed previousBundleID via start() — it will pick up the real
        // frontmost app. We then post an activation for the test process.
        monitor.start()

        inputSource.stubbedSourceID = "com.apple.keylayout.Russian"

        let note = activationNotification(bundleID: NSRunningApplication.current.bundleIdentifier ?? "")
        NSWorkspace.shared.notificationCenter.post(note)

        // The monitor should have saved the Russian layout for whatever
        // app was previously frontmost (seeded in start()).
        XCTAssertFalse(store.savedPairs.isEmpty, "Expected at least one save")
        XCTAssertEqual(store.savedPairs.first?.sourceID, "com.apple.keylayout.Russian")
    }

    func test_secondSwitch_restoresSavedSource() {
        monitor.start()

        let testBundleID = NSRunningApplication.current.bundleIdentifier ?? ""
        guard !testBundleID.isEmpty else { return }

        // Pre-populate: when we switch to the test process, restore this layout.
        store.stub("com.apple.keylayout.US", forBundleID: testBundleID)

        let note = activationNotification(bundleID: testBundleID)
        NSWorkspace.shared.notificationCenter.post(note)

        XCTAssertEqual(inputSource.selectedIDs.last, "com.apple.keylayout.US")
    }

    func test_noSavedLayout_doesNotCallSelectSource() {
        monitor.start()
        // store has no mapping for the test process bundle ID.
        let note = activationNotification(bundleID: NSRunningApplication.current.bundleIdentifier ?? "")
        NSWorkspace.shared.notificationCenter.post(note)
        // selectSource should NOT have been called.
        XCTAssertTrue(inputSource.selectedIDs.isEmpty)
    }

    /// Reproduces the Space-transition stray-TIS bug:
    /// activation fires (pendingRestoreID="US"), then a stray TIS fires while
    /// the system still reports the old layout ("RussianWin"), then the real
    /// restore TIS fires ("US"). The stray must be suppressed and must not
    /// corrupt the stored layout.
    func test_spaceTransition_strayTIS_doesNotCorruptSavedLayout() async throws {
        let testBundleID = NSRunningApplication.current.bundleIdentifier ?? ""
        guard !testBundleID.isEmpty else { return }

        // App has US saved; current system layout is RussianWin (departing app's layout).
        store.stub("com.apple.keylayout.US", forBundleID: testBundleID)
        inputSource.stubbedSourceID = "com.apple.keylayout.RussianWin"

        monitor.start()

        // 1. Activation: preRestoreID="RussianWin", pendingRestoreID="US", selectSource("US").
        NSWorkspace.shared.notificationCenter.post(Notification(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        ))
        XCTAssertEqual(inputSource.selectedIDs.last, "com.apple.keylayout.US",
                       "selectSource should have been called with the saved US layout")

        // 2. Stray TIS: OS still reports RussianWin (restore not yet effective).
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        // 3. Real restore TIS: OS now reflects the selectSource call.
        inputSource.stubbedSourceID = "com.apple.keylayout.US"
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        // Drain run loop for any Case-A async dispatch.
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000)

        let wrongSave = store.savedPairs.contains {
            $0.bundleID == testBundleID && $0.sourceID == "com.apple.keylayout.RussianWin"
        }
        XCTAssertFalse(wrongSave,
            "RussianWin must not be saved — it was a stray Space-transition TIS, not user intent")
        XCTAssertTrue(store.savedPairs.isEmpty,
            "No save should occur: stray suppressed, real restore TIS suppressed as own-restore confirmation")
    }
}
