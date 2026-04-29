import Foundation
import SwiftUI
import CarddexCore
import CarddexCatalog
import CarddexScanner

#if canImport(UIKit)
import UIKit

/// A card the user has captured during the current scanning session but has
/// not yet saved to their collection. Held in memory only; persisted via
/// `ReviewCapturedCardsView` when the user taps **Save**.
public struct CapturedCard: Identifiable, Hashable {
    public let id: UUID = UUID()
    public let capturedAt: Date
    public let imageData: Data            // HEIC bytes for the perspective-corrected crop
    public let scanResult: CapturedScanResult

    /// Editable fields, prefilled from the catalog match. The user can change
    /// any of these on the review screen before saving.
    public var draft: CardDraft

    public init(scanResult: CapturedScanResult, imageData: Data, draft: CardDraft) {
        self.capturedAt = Date()
        self.imageData = imageData
        self.scanResult = scanResult
        self.draft = draft
    }

    public var thumbnail: UIImage? {
        UIImage(data: imageData)
    }
}

/// Snapshot of the relevant fields from `CardScanner.Result` so the value
/// type stays `Sendable`/`Hashable` and we don't carry the whole pipeline
/// output around.
public struct CapturedScanResult: Hashable, Sendable {
    public var bestCardId: String?
    public var bestSetId: String?
    public var bestNumber: String?
    public var confidence: Double
    public var ocrText: String
    public var tier: Scan.Tier
    public var alternates: [Scan.Alternate]
}

/// User-editable card metadata shown in the review screen. We seed this from
/// the catalog row when the scanner identifies a known card, falling back to
/// values parsed from the OCR text otherwise.
public struct CardDraft: Hashable {
    public var name: String
    public var setName: String
    public var setId: String
    public var number: String
    public var rarity: String
    public var types: String                       // comma-separated, free-form
    public var supertype: String                   // "Pokémon", "Trainer", "Energy"
    public var quantity: Int
    public var condition: CollectionItem.Condition
    public var variant: CollectionItem.Variant
    public var language: String
    public var notes: String

    public init(name: String = "", setName: String = "", setId: String = "",
                number: String = "", rarity: String = "", types: String = "",
                supertype: String = "", quantity: Int = 1,
                condition: CollectionItem.Condition = .nearMint,
                variant: CollectionItem.Variant = .normal,
                language: String = "en", notes: String = "") {
        self.name = name; self.setName = setName; self.setId = setId
        self.number = number; self.rarity = rarity; self.types = types
        self.supertype = supertype; self.quantity = quantity
        self.condition = condition; self.variant = variant
        self.language = language; self.notes = notes
    }

    /// Build a draft from a catalog match. Falls back to parsed OCR + the
    /// scanner result for fields when the match isn't in the catalog yet.
    public static func from(scan: CapturedScanResult, catalogCard: PokemonCard?) -> CardDraft {
        if let card = catalogCard {
            return CardDraft(
                name: card.name,
                setName: card.setName,
                setId: card.setId,
                number: card.number,
                rarity: card.rarity ?? "",
                types: card.types.joined(separator: ", "),
                supertype: card.supertype ?? "",
                quantity: 1,
                condition: .nearMint,
                variant: .normal,
                language: "en",
                notes: ""
            )
        }
        return CardDraft(
            name: scan.ocrText.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? "Unknown card",
            setName: scan.bestSetId ?? "",
            setId: scan.bestSetId ?? "",
            number: scan.bestNumber ?? "",
            rarity: "",
            types: "",
            supertype: "",
            quantity: 1
        )
    }
}
#endif
