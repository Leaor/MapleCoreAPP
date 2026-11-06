import Foundation

/// Everything the app keeps on this iPhone. Local-first: the UI reads this, never the network.
public struct Snapshot: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var savedAt: Date
    public var account: Account?
    public var activeRole: AppRole?
    public var staff: [StaffMember]
    public var crews: [Crew]
    public var customers: [Customer]
    public var properties: [Property]
    public var routes: [Route]
    public var visitRecords: [VisitRecord]
    public var documents: [PropertyDocument]
    public var threads: [MessageThread]
    public var quotes: [Quote]
    public var invoices: [Invoice]
    public var snowEvent: SnowEvent?
    public var weather: Weather
    public var outbox: [OutboxItem]
    public var conflicts: [SyncConflict]
    public var settings: AppSettings
    public var notificationPrefs: NotificationPreferences
    public var locationSharing: LocationSharing
    public var shift: Shift?
    public var activeVisit: VisitSession?
    public var hasCompletedPermissions: Bool
}

public protocol SnapshotStoring: Sendable {
    func load() throws -> Snapshot?
    func save(_ snapshot: Snapshot) throws
    func clear() throws
}

/// JSON file in Application Support, written atomically. Small enough for Phase 1 fixtures;
/// Phase 2 moves the outbox and caches to SwiftData once the server schema is fixed.
public struct FileSnapshotStore: SnapshotStoring {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func applicationSupport(fileName: String = "maplecore-snapshot.json") -> FileSnapshotStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileSnapshotStore(url: base.appendingPathComponent("MapleCore", isDirectory: true).appendingPathComponent(fileName))
    }

    public func load() throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(Snapshot.self, from: data)
        return snapshot.version == Snapshot.currentVersion ? snapshot : nil
    }

    public func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// In-memory store for previews and tests.
public final class MemorySnapshotStore: SnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Snapshot?

    public init(_ snapshot: Snapshot? = nil) { stored = snapshot }

    public func load() throws -> Snapshot? { lock.withLock { stored } }
    public func save(_ snapshot: Snapshot) throws { lock.withLock { stored = snapshot } }
    public func clear() throws { lock.withLock { stored = nil } }
}
