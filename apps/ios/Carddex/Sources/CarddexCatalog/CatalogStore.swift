import Foundation
import CarddexCore

/// Loads and serves both the holofoil-viewer catalog (bundled, small) and the
/// full Pokémon TCG catalog (downloaded on first launch and cached on disk).
public actor CatalogStore {

    public static let shared = CatalogStore()

    private var holofoilCatalog: [HolofoilCatalogCard] = []
    private var pokemonCards: [PokemonCard] = []
    private var pokemonSets: [PokemonSet] = []
    private var byKey: [CardKey: PokemonCard] = [:]
    private var byName: [String: [PokemonCard]] = [:]

    private init() {}

    // MARK: - Bootstrap

    /// Loads the bundled holofoil catalog from the package's resource bundle
    /// and the cached Pokémon catalog from the app's documents dir, if present.
    public func bootstrap() async {
        if holofoilCatalog.isEmpty {
            holofoilCatalog = (try? loadHolofoilCatalog()) ?? []
        }
        if pokemonCards.isEmpty {
            if let cached = try? loadCachedPokemonCatalog() {
                installPokemonCatalog(cached.cards, sets: cached.sets)
            } else if let bundled = try? loadBundledPokemonCatalog() {
                installPokemonCatalog(bundled.cards, sets: bundled.sets)
            }
        }
    }

    // MARK: - Reads

    public func allHolofoilCards() -> [HolofoilCatalogCard] { holofoilCatalog }
    public func allSets() -> [PokemonSet] { pokemonSets }
    public func allCards() -> [PokemonCard] { pokemonCards }

    public func card(forKey key: CardKey) -> PokemonCard? { byKey[key] }
    public func card(byId id: String) -> PokemonCard? {
        pokemonCards.first { $0.id == id }
    }

    /// Case-insensitive name search. Returns up to `limit` matches ordered by
    /// closest prefix match.
    public func search(name query: String, limit: Int = 25) -> [PokemonCard] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var results: [PokemonCard] = []
        for (key, cards) in byName where key.contains(needle) {
            results.append(contentsOf: cards)
            if results.count >= limit * 4 { break }
        }
        return Array(results
            .sorted { lhs, rhs in
                rank(name: lhs.name.lowercased(), needle: needle)
                    < rank(name: rhs.name.lowercased(), needle: needle)
            }
            .prefix(limit))
    }

    /// Look up the TCG card for a parsed `(setId, number)`.
    public func resolve(setId: String, number: String) -> PokemonCard? {
        byKey[CardKey(setId: setId, number: number)]
    }

    // MARK: - Catalog refresh

    /// Replaces the cached catalog with a freshly downloaded copy. Persists to
    /// the documents dir for next launch.
    public func install(cards: [PokemonCard], sets: [PokemonSet], saveToDisk: Bool = true) async throws {
        installPokemonCatalog(cards, sets: sets)
        if saveToDisk {
            let dir = try cacheDir()
            try JSONEncoder().encode(cards).write(to: dir.appendingPathComponent("cards.json"))
            try JSONEncoder().encode(sets).write(to: dir.appendingPathComponent("sets.json"))
        }
    }

    // MARK: - Internal

    private func installPokemonCatalog(_ cards: [PokemonCard], sets: [PokemonSet]) {
        self.pokemonCards = cards
        self.pokemonSets = sets
        var k: [CardKey: PokemonCard] = [:]
        var n: [String: [PokemonCard]] = [:]
        for c in cards {
            k[CardKey(setId: c.setId, number: c.number)] = c
            n[c.name.lowercased(), default: []].append(c)
        }
        self.byKey = k
        self.byName = n
    }

    private func rank(name: String, needle: String) -> Int {
        if name == needle { return 0 }
        if name.hasPrefix(needle) { return 1 }
        if name.contains(needle) { return 2 }
        return 3
    }

    private func loadHolofoilCatalog() throws -> [HolofoilCatalogCard] {
        guard let url = Bundle.module.url(forResource: "holofoil-catalog", withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([HolofoilCatalogCard].self, from: data)
    }

    private func loadBundledPokemonCatalog() throws -> (cards: [PokemonCard], sets: [PokemonSet]) {
        guard let cardsURL = Bundle.module.url(forResource: "pokemon-cards", withExtension: "json"),
              let setsURL  = Bundle.module.url(forResource: "pokemon-sets",  withExtension: "json") else {
            return ([], [])
        }
        let cards = try JSONDecoder().decode([PokemonCard].self, from: Data(contentsOf: cardsURL))
        let sets  = try JSONDecoder().decode([PokemonSet].self,  from: Data(contentsOf: setsURL))
        return (cards, sets)
    }

    private func loadCachedPokemonCatalog() throws -> (cards: [PokemonCard], sets: [PokemonSet]) {
        let dir = try cacheDir()
        let cardsURL = dir.appendingPathComponent("cards.json")
        let setsURL  = dir.appendingPathComponent("sets.json")
        guard FileManager.default.fileExists(atPath: cardsURL.path),
              FileManager.default.fileExists(atPath: setsURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let cards = try JSONDecoder().decode([PokemonCard].self, from: Data(contentsOf: cardsURL))
        let sets  = try JSONDecoder().decode([PokemonSet].self,  from: Data(contentsOf: setsURL))
        return (cards, sets)
    }

    private func cacheDir() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Canonical identity for a Pokémon card.
public struct CardKey: Hashable, Sendable {
    public let setId: String
    public let number: String
    public init(setId: String, number: String) {
        self.setId = setId; self.number = number
    }
}
