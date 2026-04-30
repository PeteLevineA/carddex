import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Capability-gated **Tier B** verifier. Wraps Apple's Foundation Models
/// framework when it's available (Apple Intelligence-capable devices on
/// iOS 18.1+); otherwise the call is a no-op and Tier-A ranking stands.
///
/// The verifier never calls the network — Foundation Models runs the on-device
/// LLM inside the system process.
public enum FoundationModelsVerifier {

    /// Re-rank `candidates` given OCR text, returning the new ranked list.
    /// Returns `nil` if the framework / Apple Intelligence isn't available.
    public static func verify(ocrText: String,
                              candidates: ArraySlice<CardScanner.Match>) async -> [CardScanner.Match]? {
        #if canImport(FoundationModels)
        guard isAvailable() else { return nil }
        do {
            let session = LanguageModelSession()
            let prompt = makePrompt(ocrText: ocrText, candidates: Array(candidates))
            let response = try await session.respond(
                to: prompt,
                generating: VerifierResponse.self
            )
            return mergeRanking(originals: Array(candidates), llm: response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Capability detection

    public static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 18.1, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Prompt + response

    private static func makePrompt(ocrText: String, candidates: [CardScanner.Match]) -> String {
        let candidateLines = candidates.enumerated().map { index, match in
            "\(index). cardId=\(match.cardId) setId=\(match.setId) number=\(match.number) currentConfidence=\(String(format: "%.2f", match.confidence))"
        }.joined(separator: "\n")

        return """
        You are a Pokémon TCG identification assistant running fully on-device.
        Re-rank the candidates below using the OCR text from a single card scan.
        Only choose from the provided candidates. Respond with structured JSON
        matching the requested schema; do not invent new card IDs.

        OCR text:
        \(ocrText)

        Candidates:
        \(candidateLines)
        """
    }
}

#if canImport(FoundationModels)
@Generable
private struct VerifierResponse: Codable, Sendable {
    @Guide(description: "Ranked card IDs, best first; subset of provided candidates.")
    var rankedCardIds: [String]

    @Guide(description: "Confidence in [0,1] for the top choice.")
    var topConfidence: Double

    @Guide(description: "Short human-readable rationale (<= 240 chars).")
    var reason: String
}
#else
private struct VerifierResponse: Codable, Sendable {
    var rankedCardIds: [String]
    var topConfidence: Double
    var reason: String
}
#endif

private func mergeRanking(originals: [CardScanner.Match],
                          llm: VerifierResponse) -> [CardScanner.Match] {
    let byId = Dictionary(uniqueKeysWithValues: originals.map { ($0.cardId, $0) })
    var out: [CardScanner.Match] = []
    for id in llm.rankedCardIds {
        if let m = byId[id] { out.append(m) }
    }
    // Append any candidates the LLM skipped, preserving original order.
    let seen = Set(out.map { $0.cardId })
    out.append(contentsOf: originals.filter { !seen.contains($0.cardId) })
    if let first = out.first {
        // Boost the LLM-chosen top by `topConfidence` while keeping it in [0,1].
        let boosted = max(first.confidence, min(1.0, llm.topConfidence))
        out[0] = CardScanner.Match(
            cardId: first.cardId, setId: first.setId, number: first.number,
            confidence: boosted
        )
    }
    return out
}
