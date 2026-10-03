import Foundation

/// Hands one save between Macs through a folder the user already syncs (iCloud Drive, Dropbox, …) — #257.
///
/// This is the existing full-state transfer (`SaveTransfer`) with a remembered location, not a merge:
/// one save, one owner at a time. Nothing is loaded or overwritten without the user confirming —
/// the app only *notices* that another Mac left a save it has not seen yet and offers it.
///
/// "Seen" is tracked by the file's identity (`sourceDeviceID` + `exportedAt`), not by comparing
/// timestamps: two Macs' clocks can disagree, and an "is it newer?" check would silently skip a
/// save written on a Mac whose clock runs behind.
@MainActor
final class SaveSyncFolder {
    static let fileName = "PokeTokenBar-Save.json"

    private static let folderKey = "saveSyncFolderPath"
    private static let deviceIDKey = "saveSyncDeviceID"
    private static let lastSeenKey = "saveSyncLastSeen"

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    /// The chosen folder. Changing it forgets what was seen, so a save already waiting in the new
    /// folder is offered once.
    var folderURL: URL? {
        get {
            guard let path = defaults.string(forKey: Self.folderKey), !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            defaults.set(newValue?.path, forKey: Self.folderKey)
            defaults.removeObject(forKey: Self.lastSeenKey)
        }
    }

    var fileURL: URL? { folderURL?.appendingPathComponent(Self.fileName) }

    /// Stable per-install id, created on first use. Device *names* are not unique (two "MacBook Pro"s).
    var deviceID: String {
        if let id = defaults.string(forKey: Self.deviceIDKey), !id.isEmpty { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.deviceIDKey)
        return id
    }

    /// The save in the folder. nil = no folder or no file yet. Throws when a file exists but is not
    /// a readable save (`SaveTransferError`), so the caller can say so instead of acting as if empty.
    func read() throws -> SaveEnvelope? {
        guard let folder = folderURL, let url = fileURL else { return nil }
        guard fileManager.fileExists(atPath: url.path) else {
            // iCloud Drive with "Optimize Mac Storage" keeps only a `.<name>.icloud` placeholder until
            // the file is requested; ask for it so the next check finds the real file.
            let placeholder = folder.appendingPathComponent(".\(Self.fileName).icloud")
            if fileManager.fileExists(atPath: placeholder.path) {
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }
            return nil
        }
        return try SaveTransfer.decode(try Data(contentsOf: url))
    }

    /// Whether `envelope` was left by another Mac and has not been loaded, declined, or written here.
    /// A file without a device id (a manual export dropped into the folder) counts as another Mac's.
    func isUnseenFromAnotherMac(_ envelope: SaveEnvelope) -> Bool {
        envelope.sourceDeviceID != deviceID && Self.identity(envelope) != defaults.string(forKey: Self.lastSeenKey)
    }

    /// The save to offer at launch/wake, if any. Read failures are logged and offer nothing — a
    /// broken or half-synced file must not interrupt the user on every wake.
    func pendingHandoff() -> SaveEnvelope? {
        do {
            guard let envelope = try read(), isUnseenFromAnotherMac(envelope) else { return nil }
            return envelope
        } catch {
            AppLog.write("save sync: folder save unreadable: \(error)")
            return nil
        }
    }

    /// Writing would replace a save from another Mac that this Mac never took in → ask first.
    func needsOverwriteConfirmation(existing: SaveEnvelope?) -> Bool {
        existing.map(isUnseenFromAnotherMac) ?? false
    }

    /// Writes an encoded save to the folder and records it as seen. The data is decoded first so
    /// the recorded identity is exactly what lands on disk (ISO-8601 drops sub-second precision).
    @discardableResult
    func write(_ data: Data) throws -> SaveEnvelope {
        guard let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        let envelope = try SaveTransfer.decode(data)
        try data.write(to: url, options: .atomic)
        markSeen(envelope)
        return envelope
    }

    /// Loaded or declined → do not offer this file again.
    func markSeen(_ envelope: SaveEnvelope) {
        defaults.set(Self.identity(envelope), forKey: Self.lastSeenKey)
    }

    private static func identity(_ envelope: SaveEnvelope) -> String {
        "\(envelope.sourceDeviceID ?? "-")|\(envelope.exportedAt.timeIntervalSince1970)"
    }
}
