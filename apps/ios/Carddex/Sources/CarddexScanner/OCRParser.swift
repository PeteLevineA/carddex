import Foundation

/// Parses raw OCR output from a Pokémon card into the fields the identifier
/// needs. Tolerant of messy line ordering and stray whitespace.
public enum OCRParser {

    public struct Parsed: Sendable, Equatable {
        public var name: String?
        /// Raw collector number, e.g. "4" from "4/165".
        public var number: String?
        /// Set total printed at the bottom right, e.g. "165".
        public var printedTotal: Int?
        /// A best-effort hint at the set id (PTCGO code or printed series text).
        public var setHint: String?
        public var hp: Int?
        public var artist: String?
        public init() {}
    }

    /// Regex anchors the canonical "<n>/<total>" collector marker.
    static let collectorRegex = #/(\d{1,3})\s*\/\s*(\d{1,3})/#

    public static func parse(_ text: String) -> Parsed {
        var parsed = Parsed()
        let lines = text
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Collector number: search every line; the bottom-of-card marker wins.
        for line in lines.reversed() {
            if let match = try? collectorRegex.firstMatch(in: line) {
                parsed.number = String(match.output.1)
                parsed.printedTotal = Int(String(match.output.2))
                break
            }
        }

        // HP appears near the top: "HP 120" or "120 HP".
        for line in lines.prefix(5) {
            let upper = line.uppercased()
            if upper.contains("HP"),
               let n = upper.split(separator: " ").compactMap({ Int($0) }).first {
                parsed.hp = n
                break
            }
        }

        // Card name heuristic: first non-trivial line that isn't HP/number.
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("HP") { continue }
            if (try? collectorRegex.firstMatch(in: line)) != nil { continue }
            if line.count < 2 { continue }
            parsed.name = line
            break
        }

        // Illustrator credit: "Illus. <name>"
        if let illus = lines.first(where: { $0.lowercased().hasPrefix("illus") }) {
            parsed.artist = illus.replacingOccurrences(of: "Illus.", with: "")
                .trimmingCharacters(in: .whitespaces)
        }

        // Set hint: PTCGO code is often two-three uppercase letters near the
        // bottom (e.g. "MEW 151"). We surface the rightmost token of length
        // 2-4 letters as a heuristic; the catalog layer validates against
        // `PokemonSet.ptcgoCode`.
        for line in lines.suffix(4) {
            for token in line.split(whereSeparator: { !$0.isLetter }) {
                if (2...4).contains(token.count), token.allSatisfy(\.isUppercase) {
                    parsed.setHint = String(token)
                }
            }
            if parsed.setHint != nil { break }
        }

        return parsed
    }
}
