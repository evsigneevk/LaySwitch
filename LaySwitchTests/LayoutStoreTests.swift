import XCTest
@testable import LaySwitch

@MainActor
final class LayoutStoreTests: XCTestCase {

    private var tempURL: URL!
    private var store: LayoutStore!

    override func setUp() {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        store = LayoutStore(storageURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Tests

    func test_saveAndRetrieve() {
        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")
        XCTAssertEqual(
            store.sourceID(forBundleID: "com.apple.Safari"),
            "com.apple.keylayout.US"
        )
    }

    func test_unknownBundleIDReturnsNil() {
        XCTAssertNil(store.sourceID(forBundleID: "com.unknown.app"))
    }

    func test_overwrite_lastValueWins() {
        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")
        store.setSourceID("com.apple.keylayout.Russian", forBundleID: "com.apple.Safari")
        XCTAssertEqual(
            store.sourceID(forBundleID: "com.apple.Safari"),
            "com.apple.keylayout.Russian"
        )
    }

    func test_multipleApps_areStoredIndependently() {
        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")
        store.setSourceID("com.apple.keylayout.Russian", forBundleID: "com.apple.Terminal")
        XCTAssertEqual(store.sourceID(forBundleID: "com.apple.Safari"), "com.apple.keylayout.US")
        XCTAssertEqual(store.sourceID(forBundleID: "com.apple.Terminal"), "com.apple.keylayout.Russian")
    }

    func test_noOpWrite_doesNotChangeDiskIfValueUnchanged() throws {
        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")

        let firstModDate = try FileManager.default
            .attributesOfItem(atPath: tempURL.path)[.modificationDate] as? Date

        // Short sleep to ensure the mod-date would differ if a write occurred.
        Thread.sleep(forTimeInterval: 0.05)

        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")

        let secondModDate = try FileManager.default
            .attributesOfItem(atPath: tempURL.path)[.modificationDate] as? Date

        XCTAssertEqual(firstModDate, secondModDate, "File was written again despite no change")
    }

    func test_persistsAcrossReinit() {
        store.setSourceID("com.apple.keylayout.US", forBundleID: "com.apple.Safari")

        // Create a new instance pointing at the same file.
        let store2 = LayoutStore(storageURL: tempURL)
        XCTAssertEqual(
            store2.sourceID(forBundleID: "com.apple.Safari"),
            "com.apple.keylayout.US"
        )
    }
}
