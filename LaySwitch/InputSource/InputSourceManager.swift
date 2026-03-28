import Carbon.HIToolbox

// MARK: - Protocol for testability

@MainActor
protocol InputSourceManaging {
    func currentSourceID() -> String?
    @discardableResult func selectSource(withID id: String) -> Bool
}

// MARK: - Implementation

/// Wraps the Carbon Text Input Services (TIS) API.
/// All methods must be called on the main thread — TIS interacts with the
/// HIToolbox event system which is main-thread-bound.
@MainActor
struct InputSourceManager: InputSourceManaging {

    /// Returns the bundle-identifier-style string for the active keyboard layout,
    /// e.g. "com.apple.keylayout.US" or "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman".
    func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return sourceID(from: source)
    }

    /// Activates the input source whose `kTISPropertyInputSourceID` matches `id`.
    /// Returns `true` if the source was found and selected, `false` otherwise.
    @discardableResult
    func selectSource(withID id: String) -> Bool {
        guard let source = findSource(withID: id) else { return false }
        TISSelectInputSource(source)
        return true
    }

    // MARK: - Private helpers

    private func findSource(withID id: String) -> TISInputSource? {
        let filter: NSDictionary = [
            kTISPropertyInputSourceID as String: id
        ]
        guard
            let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
            let array = cfList as? [TISInputSource],
            let source = array.first
        else { return nil }
        return source
    }

    /// Reads the `kTISPropertyInputSourceID` property as a Swift String.
    private func sourceID(from source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        // The pointer is owned by the TISInputSource — use takeUnretainedValue.
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
