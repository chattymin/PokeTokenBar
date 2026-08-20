import CloudKit

/// Lightweight iCloud CloudKit sync for PhonePayload.
/// Uses a single CKRecord with a JSON blob — simple last-write-wins.
public enum CloudKitSync {
    static let containerID = "iCloud.io.github.chattymin.poketokenbar"
    static let recordType = "Payload"
    static let recordID = CKRecord.ID(recordName: "PhonePayloadCurrent")
    static let payloadField = "json"
    static let updatedField = "updatedAt"

    // MARK: - Write

    public static func save(_ payload: PhonePayload) async throws {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CloudKitSyncError.encodingFailed
        }
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[payloadField] = json
        record[updatedField] = Date()
        try await database().save(record)
    }

    // MARK: - Read

    public static func fetch() async throws -> PhonePayload? {
        do {
            let record = try await database().record(for: recordID)
            guard let json = record[payloadField] as? String,
                  let data = json.data(using: .utf8) else { return nil }
            return try JSONDecoder().decode(PhonePayload.self, from: data)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    // MARK: - Delete

    public static func delete() async throws {
        try await database().deleteRecord(withID: recordID)
    }

    // MARK: - Account Check

    public static func isAvailable() async -> Bool {
        (try? await CKContainer(identifier: containerID).accountStatus()) == .available
    }

    // MARK: - Private

    private static func database() -> CKDatabase {
        CKContainer(identifier: containerID).privateCloudDatabase
    }
}

public enum CloudKitSyncError: LocalizedError {
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode payload"
        }
    }
}
