import Foundation
import SwiftData

/// Centralised SwiftData stack. Uses CloudKit when an iCloud container is
/// configured (entitlement set in the app target); otherwise falls back to a
/// local-only store so the package builds for tests.
public enum CarddexPersistence {

    /// Builds a `ModelContainer` with all Carddex schemas registered.
    /// Pass `inMemory: true` for unit tests.
    public static func makeModelContainer(inMemory: Bool = false,
                                          cloudKitContainerID: String? = nil) throws -> ModelContainer {
        let schema = Schema([
            CollectionItem.self,
            Scan.self,
        ])

        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration("Carddex", schema: schema, isStoredInMemoryOnly: true)
        } else if let cloudKitContainerID {
            config = ModelConfiguration(
                "Carddex",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        } else {
            config = ModelConfiguration("Carddex", schema: schema)
        }

        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// Filesystem helpers for storing scan images outside the SwiftData store.
public enum CarddexStorage {
    public static var scansDirectory: URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let scans = base.appendingPathComponent("scans", isDirectory: true)
        try? FileManager.default.createDirectory(at: scans, withIntermediateDirectories: true)
        return scans
    }

    public static func relativePath(for fileName: String) -> String {
        "scans/\(fileName)"
    }

    public static func absoluteURL(forRelativePath path: String) -> URL {
        let base = try! FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent(path)
    }
}
