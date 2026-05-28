import CloudKit
import Foundation
#if os(macOS)
import Security
#endif

@MainActor
protocol CloudSyncServiceProtocol {
    func fetchSnapshot() async throws -> CloudSyncSnapshot?
    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws
}

@MainActor
final class CloudSyncService: CloudSyncServiceProtocol {
    nonisolated static let defaultContainerIdentifier = "iCloud.io.github.ghkdqhrbals.StudyMate"

    private let container: CKContainer
    private let database: CKDatabase
    private let recordID = CKRecord.ID(recordName: "private-study-snapshot")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(containerIdentifier: String = CloudSyncService.defaultContainerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    nonisolated static func canUseCloudKitContainer(identifier: String = defaultContainerIdentifier) -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlementValue = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else {
            return false
        }

        guard let containerIdentifiers = entitlementValue as? [String] else {
            return false
        }

        return containerIdentifiers.contains(identifier)
        #else
        return true
        #endif
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot? {
        do {
            let record = try await database.record(for: recordID)
            return try snapshot(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        let record: CKRecord

        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: "StudyMateSnapshot", recordID: recordID)
        }

        let data = try encoder.encode(snapshot)
        record["updatedAt"] = snapshot.updatedAt as NSDate
        record["schemaVersion"] = snapshot.schemaVersion as NSNumber
        record["payload"] = try makeAsset(data: data)

        _ = try await database.save(record)
    }

    private func snapshot(from record: CKRecord) throws -> CloudSyncSnapshot? {
        if let asset = record["payload"] as? CKAsset,
           let fileURL = asset.fileURL {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(CloudSyncSnapshot.self, from: data)
        }

        if let data = record["payloadData"] as? Data {
            return try decoder.decode(CloudSyncSnapshot.self, from: data)
        }

        return nil
    }

    private func makeAsset(data: Data) throws -> CKAsset {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyMateCloudSync", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        try data.write(to: fileURL, options: .atomic)
        return CKAsset(fileURL: fileURL)
    }
}

enum CloudSyncFailureKind: Equatable {
    case quotaExceeded
    case notAuthenticated
    case permissionDenied
    case network
    case serviceUnavailable
    case rateLimited
    case limitExceeded
    case conflict
    case unavailable
    case unknown
}

enum CloudSyncErrorClassifier {
    static func kind(for error: Error) -> CloudSyncFailureKind {
        guard let cloudKitError = error as? CKError else {
            return .unknown
        }

        if cloudKitError.code == .partialFailure,
           let firstPartialError = cloudKitError.partialErrorsByItemID?.values.first {
            return kind(for: firstPartialError)
        }

        switch cloudKitError.code {
        case .quotaExceeded:
            return .quotaExceeded
        case .notAuthenticated:
            return .notAuthenticated
        case .permissionFailure, .badContainer, .missingEntitlement:
            return .permissionDenied
        case .networkUnavailable, .networkFailure:
            return .network
        case .serviceUnavailable, .zoneBusy:
            return .serviceUnavailable
        case .requestRateLimited:
            return .rateLimited
        case .limitExceeded, .serverRejectedRequest, .assetFileNotFound, .assetFileModified:
            return .limitExceeded
        case .serverRecordChanged, .constraintViolation:
            return .conflict
        case .managedAccountRestricted, .accountTemporarilyUnavailable:
            return .unavailable
        default:
            return .unknown
        }
    }
}
