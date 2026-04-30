import XCTest
@testable import CarddexCatalog
@testable import CarddexCore

final class CatalogStoreTests: XCTestCase {

    func testHolofoilCatalogLoadsFromBundle() async {
        let store = CatalogStore.shared
        await store.bootstrap()
        let cards = await store.allHolofoilCards()
        XCTAssertFalse(cards.isEmpty, "bundled holofoil-catalog.json should produce cards")
    }

    func testInstallAndResolve() async throws {
        let store = CatalogStore.shared
        let card = PokemonCard(
            id: "test-1", name: "Testachu",
            setId: "test", setName: "Testset", series: "Test",
            number: "1", printedTotal: 1, rarity: nil,
            supertype: nil, subtypes: [], types: [],
            hp: nil, nationalPokedexNumbers: [], artist: nil, flavorText: nil,
            images: .init(small: nil, large: nil), prices: nil
        )
        try await store.install(cards: [card], sets: [], saveToDisk: false)
        let resolved = await store.resolve(setId: "test", number: "1")
        XCTAssertEqual(resolved?.id, "test-1")
        let bySearch = await store.search(name: "Test", limit: 5)
        XCTAssertTrue(bySearch.contains(where: { $0.id == "test-1" }))
    }
}
