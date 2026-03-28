import Foundation
import OSLog

private let log = Logger(subsystem: "com.layswitch.app", category: "LayoutStore")

// MARK: - Protocol for testability

@MainActor
protocol LayoutStoring {
    func sourceID(forBundleID bundleID: String) -> String?
    func setSourceID(_ sourceID: String, forBundleID bundleID: String)
}

// MARK: - Implementation

/// Persists the per-app input source mapping as a JSON file in Application Support.
/// The file is written atomically so a crash mid-write never corrupts stored data.
@MainActor
final class LayoutStore: LayoutStoring {

    private var mappings: [String: String] = [:]
    private let fileURL: URL

    // MARK: - Init

    /// Production initialiser — stores data in ~/Library/Application Support/Layswitcher/.
    convenience init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("LaySwitch", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        self.init(storageURL: dir.appendingPathComponent("layouts.json"))
    }

    /// Designated initialiser. Accepts a custom URL so tests can point to a temp directory.
    init(storageURL: URL) {
        fileURL = storageURL
        load()
    }

    // MARK: - LayoutStoring

    func sourceID(forBundleID bundleID: String) -> String? {
        mappings[bundleID]
    }

    func setSourceID(_ sourceID: String, forBundleID bundleID: String) {
        // Skip disk I/O when nothing changed.
        guard mappings[bundleID] != sourceID else { return }
        log.info("Saved \(sourceID, privacy: .public) for \(bundleID, privacy: .public)")
        mappings[bundleID] = sourceID
        save()
    }

    // MARK: - Private

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        mappings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
