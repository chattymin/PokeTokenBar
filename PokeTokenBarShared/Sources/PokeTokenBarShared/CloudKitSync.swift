import CloudKit

/// Lightweight iCloud CloudKit sync for PhonePayload.
/// Uses a single CKRecord with a JSON blob — simple last-write-wins.
public enum CloudKitSync {
    static let containerID = "iCloud.io.github.chattymin.poketokenbar"
    static let recordType = "Payload"
    static let recordID = CKRecord.ID(recordName: "PhonePayloadCurrent")
    static let payloadField = "json"
    static let updatedField = "updatedAt"

    /// Process-lifetime container. Short-lived CKContainer instances can tear down the
    /// cloudd client session while operations are still pending ("Client went away before
    /// operation could be validated"), so the container must outlive every operation.
    private static let container = CKContainer(identifier: containerID)

    // MARK: - Write

    /// Last-write-wins overwrite of the single payload record.
    ///
    /// Deliberately does NOT fetch the existing record first: a failed fetch used to be
    /// swallowed by `try?` and "recovered" by inserting a fresh CKRecord under the same
    /// record name — a deterministic `serverRecordChanged` ("record to insert already
    /// exists") once the record exists. The `.allKeys` save policy overwrites the server
    /// record with no etag negotiation, so no pre-fetch is needed.
    public static func save(_ payload: PhonePayload) async throws {
        let record = try makeRecord(payload)
        let operation = makeSaveOperation(record: record)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            database().add(operation)
        }
    }

    /// Record construction (testable seam) — payload must round-trip through the json field.
    static func makeRecord(_ payload: PhonePayload) throws -> CKRecord {
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CloudKitSyncError.encodingFailed
        }
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record[payloadField] = json
        record[updatedField] = Date()
        return record
    }

    /// Save operation (testable seam) — `.allKeys` pins the etag-free overwrite policy.
    static func makeSaveOperation(record: CKRecord) -> CKModifyRecordsOperation {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: [])
        operation.savePolicy = .allKeys
        operation.qualityOfService = .utility
        return operation
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
        container.privateCloudDatabase
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
