import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog
import CarddexScanner

/// Live camera + scanning pipeline UI. Uses VisionKit `DataScannerViewController`
/// where available and falls back to `AVCaptureSession` on older devices.
public struct ScanTab: View {

    @Environment(\.modelContext) private var modelContext
    @State private var lastResult: CardScanner.Result?
    @State private var isScanning = false
    @State private var error: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CameraScannerView { image in
                    Task { await runIdentification(on: image) }
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()
                    if let result = lastResult {
                        ScanResultCard(result: result, onConfirm: confirm)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding()
                    }
                }
            }
            .overlay(alignment: .top) {
                if isScanning {
                    ProgressView("Identifying…")
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 8)
                }
            }
            .alert("Scan failed", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .navigationTitle("Scan")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
    }

    @MainActor
    private func runIdentification(on image: CGImage) async {
        isScanning = true
        defer { isScanning = false }
        let scanner = CardScanner()
        #if canImport(Vision)
        let result = await scanner.identify(image: image)
        lastResult = result
        #endif
    }

    private func confirm() {
        guard let result = lastResult, let best = result.bestMatch else { return }
        let scan = Scan(croppedImagePath: persistCrop(result))
        scan.guessedCardId = best.cardId
        scan.guessedSetId = best.setId
        scan.guessedNumber = best.number
        scan.confidence = best.confidence
        scan.alternates = result.alternates.map { Scan.Alternate(cardId: $0.cardId, setId: $0.setId, number: $0.number, confidence: $0.confidence) }
        scan.ocrText = result.ocrText
        scan.tier = result.tier
        scan.userConfirmed = true

        let item = CollectionItem(cardId: best.cardId, setId: best.setId, number: best.number)
        scan.collectionItem = item
        modelContext.insert(item)
        modelContext.insert(scan)
        try? modelContext.save()
        lastResult = nil
    }

    private func persistCrop(_ result: CardScanner.Result) -> String {
        guard let data = result.croppedImageData else { return "" }
        let name = "\(UUID().uuidString).heic"
        let url = CarddexStorage.scansDirectory.appendingPathComponent(name)
        try? data.write(to: url)
        return CarddexStorage.relativePath(for: name)
    }
}

private struct ScanResultCard: View {
    let result: CardScanner.Result
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let best = result.bestMatch {
                Text("Matched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(best.setId) · #\(best.number)")
                    .font(.headline)
                ProgressView(value: best.confidence)
                Text(String(format: "Confidence %.0f%% (Tier %@)", best.confidence * 100, result.tier.rawValue))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Couldn't find a match yet — keep the card in frame.")
                    .font(.subheadline)
            }
            HStack {
                Button("Confirm & Save", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .disabled(result.bestMatch == nil)
                Spacer()
            }
        }
    }
}
