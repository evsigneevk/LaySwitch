import Foundation

/// Manages launch-at-login by writing/removing a LaunchAgent plist
/// in ~/Library/LaunchAgents/. This approach works with ad-hoc signing
/// and requires no Apple Developer account.
///
/// The plist is picked up by launchd at the next login automatically.
@MainActor
final class LoginItemManager {

    private let label = "com.layswitch.app"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    // MARK: - Public interface

    var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    func enable() throws {
        // Resolve the actual executable path at runtime so the plist stays
        // valid regardless of where the .app lives.
        guard let executablePath = Bundle.main.executablePath else {
            throw LoginItemError.noExecutablePath
        }

        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: launchAgentsDir,
            withIntermediateDirectories: true
        )

        let plist: NSDictionary = [
            "Label": label,
            "ProgramArguments": [executablePath],
            // RunAtLoad: launchd starts the job when the plist is loaded at login.
            "RunAtLoad": true,
            // Only keep one instance running.
            "KeepAlive": false,
        ]

        guard plist.write(to: plistURL, atomically: true) else {
            throw LoginItemError.writeFailed
        }
    }

    func disable() throws {
        // If the agent is currently loaded, tell launchd to stop tracking it
        // without waiting for a reboot. Ignore errors here — the plist removal
        // below is what matters for the next-login behaviour.
        runLaunchctl(["bootout", "gui/\(getuid())/\(label)"])

        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        try FileManager.default.removeItem(at: plistURL)
    }

    func toggle() throws {
        if isEnabled {
            try disable()
        } else {
            try enable()
        }
    }

    // MARK: - Private

    /// Runs launchctl with the given arguments. Failures are non-fatal
    /// (e.g. the service may not be loaded yet).
    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}

// MARK: - Errors

enum LoginItemError: LocalizedError {
    case noExecutablePath
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noExecutablePath:
            return "Could not determine the application's executable path."
        case .writeFailed:
            return "Failed to write the LaunchAgent plist to ~/Library/LaunchAgents/."
        }
    }
}
