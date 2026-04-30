import XCTest
import SwiftData
@testable import CarddexCore

final class PersistenceTests: XCTestCase {

    func testInMemoryContainerInsertsCollectionItem() throws {
        let container = try CarddexPersistence.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        let item = CollectionItem(cardId: "sv3pt5-4", setId: "sv3pt5", number: "4")
        context.insert(item)
        try context.save()

        let descriptor = FetchDescriptor<CollectionItem>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.number, "4")
        XCTAssertEqual(fetched.first?.condition, .nearMint)
    }

    func testScanAlternatesRoundTrip() throws {
        let scan = Scan(croppedImagePath: "scans/x.heic")
        let alt = Scan.Alternate(cardId: "a", setId: "s", number: "1", confidence: 0.5)
        scan.alternates = [alt]
        XCTAssertEqual(scan.alternates.first, alt)
    }
}
