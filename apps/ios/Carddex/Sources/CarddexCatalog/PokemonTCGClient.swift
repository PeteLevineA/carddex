import Foundation
import CarddexCore

/// Thin async client for https://api.pokemontcg.io/v2.
///
/// Used as the *Tier C* identification fallback (only when the user opts in)
/// and to refresh the local catalog. Network use is gated by `Settings.allowNetwork`.
public actor PokemonTCGClient {

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var apiKey: String?
        public var pageSize: Int

        public init(baseURL: URL = URL(string: "https://api.pokemontcg.io/v2")!,
                    apiKey: String? = nil,
                    pageSize: Int = 250) {
            self.baseURL = baseURL; self.apiKey = apiKey; self.pageSize = pageSize
        }
    }

    private let session: URLSession
    private var config: Configuration

    public init(configuration: Configuration = Configuration(), session: URLSession = .shared) {
        self.config = configuration
        self.session = session
    }

    public func updateConfiguration(_ config: Configuration) {
        self.config = config
    }

    // MARK: - Search

    /// Search by free text. The TCG API uses Lucene-style queries, e.g. `name:Charizard set.id:base1`.
    public func searchCards(query: String, page: Int = 1) async throws -> [PokemonCard] {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("cards"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(config.pageSize)),
        ]
        let envelope: APIResponse<[APICard]> = try await get(components.url!)
        return envelope.data.map { $0.toCore() }
    }

    /// Convenience: `(setId, number)` lookup used by the scanner Tier C fallback.
    public func lookup(setId: String, number: String) async throws -> PokemonCard? {
        let q = "set.id:\(setId) number:\(number)"
        let results = try await searchCards(query: q, page: 1)
        return results.first
    }

    // MARK: - Bulk download (used to refresh the bundled catalog)

    public func downloadAllCards(progress: ((Int) -> Void)? = nil) async throws -> [PokemonCard] {
        var all: [PokemonCard] = []
        var page = 1
        while true {
            var components = URLComponents(url: config.baseURL.appendingPathComponent("cards"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(config.pageSize)),
                URLQueryItem(name: "orderBy", value: "set.releaseDate,number"),
            ]
            let envelope: APIResponse<[APICard]> = try await get(components.url!)
            if envelope.data.isEmpty { break }
            all.append(contentsOf: envelope.data.map { $0.toCore() })
            progress?(all.count)
            if envelope.data.count < config.pageSize { break }
            page += 1
        }
        return all
    }

    public func downloadAllSets() async throws -> [PokemonSet] {
        var all: [PokemonSet] = []
        var page = 1
        while true {
            var components = URLComponents(url: config.baseURL.appendingPathComponent("sets"),
                                           resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "pageSize", value: String(config.pageSize)),
            ]
            let envelope: APIResponse<[APISet]> = try await get(components.url!)
            if envelope.data.isEmpty { break }
            all.append(contentsOf: envelope.data.map { $0.toCore() })
            if envelope.data.count < config.pageSize { break }
            page += 1
        }
        return all
    }

    // MARK: - Internal

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let key = config.apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Wire types

private struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let page: Int?
    let pageSize: Int?
    let count: Int?
    let totalCount: Int?
}

private struct APICard: Decodable {
    let id: String
    let name: String
    let supertype: String?
    let subtypes: [String]?
    let types: [String]?
    let hp: String?
    let number: String
    let rarity: String?
    let artist: String?
    let flavorText: String?
    let nationalPokedexNumbers: [Int]?
    let images: APIImages?
    let set: APISet
    let tcgplayer: APITCGPlayer?
    let cardmarket: APICardmarket?

    func toCore() -> PokemonCard {
        PokemonCard(
            id: id, name: name,
            setId: set.id, setName: set.name, series: set.series,
            number: number, printedTotal: set.printedTotal, rarity: rarity,
            supertype: supertype, subtypes: subtypes ?? [], types: types ?? [],
            hp: hp, nationalPokedexNumbers: nationalPokedexNumbers ?? [],
            artist: artist, flavorText: flavorText,
            images: PokemonCard.Images(small: images?.small, large: images?.large),
            prices: nil
        )
    }
}

private struct APIImages: Decodable {
    let small: String?
    let large: String?
}

private struct APISet: Decodable {
    let id: String
    let name: String
    let series: String
    let printedTotal: Int?
    let total: Int?
    let releaseDate: String?
    let ptcgoCode: String?
    let images: APISetImages?

    func toCore() -> PokemonSet {
        PokemonSet(
            id: id, name: name, series: series,
            printedTotal: printedTotal ?? 0, total: total ?? 0,
            releaseDate: releaseDate ?? "",
            ptcgoCode: ptcgoCode, symbol: images?.symbol, logo: images?.logo
        )
    }
}

private struct APISetImages: Decodable { let symbol: String?; let logo: String? }
private struct APITCGPlayer: Decodable { let updatedAt: String? }
private struct APICardmarket: Decodable { let updatedAt: String? }
