import Foundation
import SwiftData

// MARK: - Catalog data (shared, read-only)

/// A Pokémon TCG set as represented in the bundled / downloaded catalog.
public struct PokemonSet: Codable, Hashable, Identifiable, Sendable {
    public let id: String          // e.g. "sv3pt5"
    public let name: String        // "151"
    public let series: String      // "Scarlet & Violet"
    public let printedTotal: Int
    public let total: Int
    public let releaseDate: String // "2023/09/22"
    public let ptcgoCode: String?
    public let symbol: String?     // remote URL of the small symbol PNG
    public let logo: String?

    public init(id: String, name: String, series: String, printedTotal: Int, total: Int,
                releaseDate: String, ptcgoCode: String?, symbol: String?, logo: String?) {
        self.id = id; self.name = name; self.series = series
        self.printedTotal = printedTotal; self.total = total; self.releaseDate = releaseDate
        self.ptcgoCode = ptcgoCode; self.symbol = symbol; self.logo = logo
    }
}

/// A canonical Pokémon card record. `(setId, number)` is the identity.
public struct PokemonCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String          // TCG API id, e.g. "sv3pt5-4"
    public let name: String
    public let setId: String
    public let setName: String
    public let series: String?
    public let number: String      // "4" or "TG14"
    public let printedTotal: Int?
    public let rarity: String?
    public let supertype: String?
    public let subtypes: [String]
    public let types: [String]
    public let hp: String?
    public let nationalPokedexNumbers: [Int]
    public let artist: String?
    public let flavorText: String?
    public let images: Images
    public let prices: Prices?

    public struct Images: Codable, Hashable, Sendable {
        public let small: String?
        public let large: String?
    }

    public struct Prices: Codable, Hashable, Sendable {
        public let updatedAt: String?
        // The TCG API returns nested provider-specific shapes; we keep them
        // as raw JSON so we can render whatever's there without locking in
        // an enum.
        public let tcgplayer: AnyCodable?
        public let cardmarket: AnyCodable?
    }
}

/// Catalog-card record for the *holofoil viewer* (matches assets/cards/catalog.json).
public struct HolofoilCatalogCard: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String?
    public let set: String?
    public let rarity: String?
    public let number: String?
    public let image: String
    public let depth: String
    public let expandedImage: String?
    public let expandedDepth: String?
    public let holoPattern: HoloPattern?
    public let holoCoverage: HoloCoverage?
    public let artworkRegion: Region?
    public let depthScale: Double?
    public let foilStrength: Double?
    public let accent: String?

    public struct Region: Codable, Hashable, Sendable {
        public let x: Double; public let y: Double; public let w: Double; public let h: Double
    }
}

public enum HoloPattern: String, Codable, CaseIterable, Sendable {
    case starlight, cosmos, tinsel, sheen
    case crackedIce  = "cracked-ice"
    case crosshatch
    case waterWeb    = "water-web"
    case sequin, fireworks, plain, none
}

public enum HoloCoverage: String, Codable, CaseIterable, Sendable {
    case full, reverse, art, stamp, none
}

// MARK: - SwiftData models (mutable, per-user, CloudKit-synced)

/// User-owned card. Multiple `CollectionItem`s can reference the same `PokemonCard`
/// (e.g. a normal and a reverse-holo copy).
@Model
public final class CollectionItem {
    @Attribute(.unique) public var id: UUID = UUID()
    public var cardId: String                 // PokemonCard.id (TCG API id)
    public var setId: String
    public var number: String
    public var quantity: Int = 1
    public var conditionRaw: String = Condition.nearMint.rawValue
    public var languageRaw: String = "en"
    public var variantRaw: String = Variant.normal.rawValue
    public var notes: String = ""
    public var addedAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Scan.collectionItem)
    public var scans: [Scan] = []

    public var condition: Condition {
        get { Condition(rawValue: conditionRaw) ?? .nearMint }
        set { conditionRaw = newValue.rawValue }
    }
    public var variant: Variant {
        get { Variant(rawValue: variantRaw) ?? .normal }
        set { variantRaw = newValue.rawValue }
    }

    public init(cardId: String, setId: String, number: String,
                quantity: Int = 1, condition: Condition = .nearMint,
                variant: Variant = .normal, language: String = "en", notes: String = "") {
        self.cardId = cardId
        self.setId = setId
        self.number = number
        self.quantity = quantity
        self.conditionRaw = condition.rawValue
        self.variantRaw = variant.rawValue
        self.languageRaw = language
        self.notes = notes
    }

    public enum Condition: String, Codable, CaseIterable, Sendable {
        case mint = "M", nearMint = "NM", lightlyPlayed = "LP",
             moderatelyPlayed = "MP", heavilyPlayed = "HP", damaged = "DMG"
    }

    public enum Variant: String, Codable, CaseIterable, Sendable {
        case normal, holo, reverseHolo = "reverse-holo",
             firstEdition = "first-edition", masterBall = "master-ball",
             pokeBall = "poke-ball", promo, alt
    }
}

/// A single scan event: the corrected crop on disk plus the identifier output.
@Model
public final class Scan {
    @Attribute(.unique) public var id: UUID = UUID()
    public var croppedImagePath: String   // relative to Application Support
    public var fullFrameImagePath: String?
    public var guessedCardId: String?
    public var guessedSetId: String?
    public var guessedNumber: String?
    public var confidence: Double = 0
    public var alternatesData: Data = Data()  // JSON-encoded [Alternate]
    public var ocrText: String = ""
    public var embedding: Data?
    public var tierRaw: String = Tier.tierA.rawValue
    public var userConfirmed: Bool = false
    public var createdAt: Date = Date()
    public var latitude: Double?
    public var longitude: Double?

    @Relationship public var collectionItem: CollectionItem?

    public var tier: Tier {
        get { Tier(rawValue: tierRaw) ?? .tierA }
        set { tierRaw = newValue.rawValue }
    }

    public var alternates: [Alternate] {
        get { (try? JSONDecoder().decode([Alternate].self, from: alternatesData)) ?? [] }
        set { alternatesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    public init(croppedImagePath: String) {
        self.croppedImagePath = croppedImagePath
    }

    public enum Tier: String, Codable, Sendable {
        case tierA = "A"   // OCR + visual hashing only
        case tierB = "B"   // + on-device LLM verification
        case tierC = "C"   // + cloud fallback
    }

    public struct Alternate: Codable, Hashable, Sendable {
        public let cardId: String
        public let setId: String
        public let number: String
        public let confidence: Double
        public init(cardId: String, setId: String, number: String, confidence: Double) {
            self.cardId = cardId; self.setId = setId; self.number = number; self.confidence = confidence
        }
    }
}

// MARK: - Helpers

/// Type-erased Codable wrapper so we can carry through provider-specific
/// price blobs without committing to a fixed shape.
public struct AnyCodable: Codable, Hashable, Sendable {
    public let value: String   // JSON-encoded original

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let data = try? JSONEncoder().encode(JSONValue(from: decoder)) {
            self.value = String(data: data, encoding: .utf8) ?? ""
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else {
            self.value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private indirect enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .number(let n):  try c.encode(n)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
}
