import Foundation
import CarddexCore
import CarddexCatalog

#if canImport(Vision)
import Vision
import CoreImage
import UIKit
#endif

/// The scanner pipeline. Owns identification but not capture (the camera UI
/// in `CarddexUI` feeds frames in).
///
/// The pipeline is intentionally tiered so it works fully offline on every
/// supported device, and gets better on devices with Apple Intelligence:
///
/// 1. **Tier A** (always on, fully offline) — Vision rectangle detection,
///    perspective correction, OCR for `(setId, number)` plus card name, and
///    a Core ML embedding lookup against the bundled catalog index.
/// 2. **Tier B** (capability-gated) — `Foundation Models` (Apple Intelligence)
///    verifies ambiguous Tier-A candidates with structured output. Skipped
///    automatically if the framework isn't available.
/// 3. **Tier C** (opt-in) — `PokemonTCGClient` lookup, only when Tier A is
///    low-confidence and the user has enabled cloud lookups in Settings.
public actor CardScanner {

    public struct Settings: Sendable {
        public var allowCloudFallback: Bool
        public var minTierAConfidenceForAutoAccept: Double
        public var minTierBConfidence: Double

        public init(allowCloudFallback: Bool = false,
                    minTierAConfidenceForAutoAccept: Double = 0.92,
                    minTierBConfidence: Double = 0.6) {
            self.allowCloudFallback = allowCloudFallback
            self.minTierAConfidenceForAutoAccept = minTierAConfidenceForAutoAccept
            self.minTierBConfidence = minTierBConfidence
        }
    }

    public struct Result: Sendable {
        public var bestMatch: Match?
        public var alternates: [Match]
        public var ocrText: String
        public var tier: Scan.Tier
        public var croppedImageData: Data?     // HEIC-encoded perspective-corrected crop
    }

    public struct Match: Sendable, Hashable {
        public let cardId: String
        public let setId: String
        public let number: String
        public let confidence: Double
    }

    private let catalog: CatalogStore
    private let cloudClient: PokemonTCGClient
    private var settings: Settings

    public init(catalog: CatalogStore = .shared,
                cloudClient: PokemonTCGClient = PokemonTCGClient(),
                settings: Settings = Settings()) {
        self.catalog = catalog
        self.cloudClient = cloudClient
        self.settings = settings
    }

    public func updateSettings(_ s: Settings) { self.settings = s }

    // MARK: - Public entry point

    #if canImport(Vision)
    /// Identify a card from a single full-frame image. Returns the best match
    /// plus alternates and the perspective-corrected crop.
    public func identify(image: CGImage) async -> Result {
        let crop = await Self.detectAndCorrect(image: image) ?? image
        let ocr = await Self.recognizeText(in: crop)
        let parsed = OCRParser.parse(ocr)

        // Tier A — primary lookup by (setId, number) when OCR found one.
        var tier: Scan.Tier = .tierA
        var ranked: [Match] = await rankByOCR(parsed: parsed)

        // Tier B — Foundation Models verification (best-effort, no-op if unavailable).
        if let top = ranked.first, top.confidence < settings.minTierAConfidenceForAutoAccept {
            if let refined = await FoundationModelsVerifier.verify(
                ocrText: ocr, candidates: ranked.prefix(5)
            ) {
                ranked = refined
                tier = .tierB
            }
        }

        // Tier C — opt-in cloud fallback if still uncertain and OCR has a key.
        if settings.allowCloudFallback,
           ranked.first?.confidence ?? 0 < settings.minTierBConfidence,
           let setId = parsed.setHint, let number = parsed.number {
            if let cloud = try? await cloudClient.lookup(setId: setId, number: number) {
                let m = Match(cardId: cloud.id, setId: cloud.setId, number: cloud.number, confidence: 0.95)
                ranked = [m] + ranked.filter { $0.cardId != m.cardId }
                tier = .tierC
            }
        }

        let cropData = Self.encodeHEIC(crop)
        return Result(
            bestMatch: ranked.first,
            alternates: Array(ranked.dropFirst().prefix(3)),
            ocrText: ocr,
            tier: tier,
            croppedImageData: cropData
        )
    }
    #endif

    // MARK: - Tier A ranking

    private func rankByOCR(parsed: OCRParser.Parsed) async -> [Match] {
        var matches: [Match] = []

        // 1. (setId, number) — strongest signal.
        if let setId = parsed.setHint, let number = parsed.number,
           let card = await catalog.resolve(setId: setId, number: number) {
            matches.append(Match(cardId: card.id, setId: card.setId, number: card.number, confidence: 0.95))
        } else if let number = parsed.number {
            // Unknown set, but number is unique enough across many sets when
            // combined with a name match.
            let candidates = (await catalog.allCards()).filter { $0.number == number }
            for c in candidates.prefix(20) {
                let nameScore = parsed.name.map { Self.nameSimilarity($0, c.name) } ?? 0.5
                matches.append(Match(cardId: c.id, setId: c.setId, number: c.number,
                                     confidence: 0.55 + 0.4 * nameScore))
            }
        }

        // 2. Name-only fallback when no number was OCR'd.
        if matches.isEmpty, let name = parsed.name {
            let hits = await catalog.search(name: name, limit: 10)
            for c in hits {
                let s = Self.nameSimilarity(name, c.name)
                matches.append(Match(cardId: c.id, setId: c.setId, number: c.number,
                                     confidence: 0.4 + 0.4 * s))
            }
        }

        return matches
            .sorted { $0.confidence > $1.confidence }
    }

    private static func nameSimilarity(_ a: String, _ b: String) -> Double {
        let la = a.lowercased(), lb = b.lowercased()
        if la == lb { return 1 }
        if la.contains(lb) || lb.contains(la) { return 0.85 }
        // Cheap Jaccard over character bigrams.
        let bigrams: (String) -> Set<String> = { s in
            var out: Set<String> = []
            let chars = Array(s)
            guard chars.count >= 2 else { return out }
            for i in 0..<(chars.count - 1) { out.insert(String(chars[i...i+1])) }
            return out
        }
        let A = bigrams(la), B = bigrams(lb)
        guard !A.isEmpty, !B.isEmpty else { return 0 }
        let inter = Double(A.intersection(B).count)
        let union = Double(A.union(B).count)
        return inter / union
    }
}

#if canImport(Vision)
import VisionKit

extension CardScanner {

    static func detectAndCorrect(image: CGImage) async -> CGImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            let request = VNDetectRectanglesRequest { req, _ in
                guard let obs = (req.results as? [VNRectangleObservation])?
                    .max(by: { $0.confidence < $1.confidence }) else {
                    cont.resume(returning: nil); return
                }
                let corrected = perspectiveCorrect(image: image, observation: obs)
                cont.resume(returning: corrected)
            }
            request.minimumConfidence = 0.6
            request.minimumAspectRatio = 0.55
            request.maximumAspectRatio = 0.85
            request.minimumSize = 0.2
            request.maximumObservations = 1
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    static func perspectiveCorrect(image: CGImage, observation: VNRectangleObservation) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let w = ci.extent.width, h = ci.extent.height
        // Vision returns normalized coords with origin bottom-left.
        let topLeft     = CGPoint(x: observation.topLeft.x * w,     y: observation.topLeft.y * h)
        let topRight    = CGPoint(x: observation.topRight.x * w,    y: observation.topRight.y * h)
        let bottomLeft  = CGPoint(x: observation.bottomLeft.x * w,  y: observation.bottomLeft.y * h)
        let bottomRight = CGPoint(x: observation.bottomRight.x * w, y: observation.bottomRight.y * h)

        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft),     forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight),    forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft),  forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        let context = CIContext()
        return context.createCGImage(output, from: output.extent)
    }

    static func recognizeText(in image: CGImage) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    static func encodeHEIC(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
#endif
