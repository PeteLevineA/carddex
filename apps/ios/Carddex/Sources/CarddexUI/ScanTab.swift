import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog
import CarddexScanner

#if canImport(UIKit)
import UIKit

/// Live camera + scanning pipeline UI.
///
/// Each successful identification adds the captured card to a session queue
/// rendered as a horizontally scrollable HUD pinned above the bottom toolbar.
/// A **Next** button opens `ReviewCapturedCardsView`, where each card gets a
/// large editable row, and a **Save** button there commits everything to the
/// SwiftData collection in one batch.
public struct ScanTab: View {

    @Environment(\.modelContext) private var modelContext

    /// Cards captured this session, awaiting review/save. Held in `@State`
    /// rather than SwiftData so abandoned sessions don't litter the store.
    @State private var capturedCards: [CapturedCard] = []
    @State private var pendingResult: PendingResult?
    @State private var isScanning = false
    @State private var error: String?
    @State private var goToReview = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CameraScannerView { image in
                    Task { await runIdentification(on: image) }
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                    if let pending = pendingResult {
                        PendingMatchCard(
                            pending: pending,
                            onAdd:    { add(pending) },
                            onDismiss: { pendingResult = nil }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    CapturedCardsHUD(cards: capturedCards) { id in
                        capturedCards.removeAll { $0.id == id }
                    }
                    NextFooter(
                        count: capturedCards.count,
                        onNext: { goToReview = true }
                    )
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
            .navigationDestination(isPresented: $goToReview) {
                ReviewCapturedCardsView(capturedCards: $capturedCards)
            }
        }
    }

    // MARK: - Pipeline

    @MainActor
    private func runIdentification(on image: CGImage) async {
        isScanning = true
        defer { isScanning = false }
        let scanner = CardScanner()
        #if canImport(Vision)
        let result = await scanner.identify(image: image)
        guard result.bestMatch != nil, let imageData = result.croppedImageData else {
            // No usable identification — let the user keep scanning.
            return
        }
        let snapshot = CapturedScanResult(
            bestCardId: result.bestMatch?.cardId,
            bestSetId:  result.bestMatch?.setId,
            bestNumber: result.bestMatch?.number,
            confidence: result.bestMatch?.confidence ?? 0,
            ocrText: result.ocrText,
            tier: result.tier,
            alternates: result.alternates.map {
                Scan.Alternate(cardId: $0.cardId, setId: $0.setId,
                               number: $0.number, confidence: $0.confidence)
            }
        )
        let catalogCard = await CatalogStore.shared.card(byId: snapshot.bestCardId ?? "")
        let draft = CardDraft.from(scan: snapshot, catalogCard: catalogCard)
        pendingResult = PendingResult(scan: snapshot, imageData: imageData, draft: draft)
        #endif
    }

    private func add(_ pending: PendingResult) {
        let captured = CapturedCard(
            scanResult: pending.scan,
            imageData: pending.imageData,
            draft: pending.draft
        )
        capturedCards.append(captured)
        pendingResult = nil
    }
}

// MARK: - Pending match card

private struct PendingResult: Identifiable, Hashable {
    let id = UUID()
    let scan: CapturedScanResult
    let imageData: Data
    let draft: CardDraft
}

private struct PendingMatchCard: View {
    let pending: PendingResult
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let img = UIImage(data: pending.imageData) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(pending.draft.name.isEmpty ? "Unknown card" : pending.draft.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(pending.draft.setName.isEmpty ? pending.draft.setId : pending.draft.setName) · #\(pending.draft.number)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: pending.scan.confidence)
                    .frame(maxWidth: 160)
            }
            Spacer()
            VStack(spacing: 6) {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to capture queue")

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss match")
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - HUD

/// Horizontally scrollable strip of captured-card thumbnails, pinned above
/// the footer. Tapping a thumbnail's "x" removes it from the queue.
struct CapturedCardsHUD: View {
    let cards: [CapturedCard]
    let onRemove: (UUID) -> Void

    var body: some View {
        Group {
            if cards.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { card in
                            CapturedThumbnail(card: card, onRemove: { onRemove(card.id) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(height: 110)
                .background(.ultraThinMaterial)
                .accessibilityLabel("Captured cards. \(cards.count) so far.")
            }
        }
    }
}

private struct CapturedThumbnail: View {
    let card: CapturedCard
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = card.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 64, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel("Remove \(card.draft.name) from queue")
        }
    }
}

// MARK: - Footer

private struct NextFooter: View {
    let count: Int
    let onNext: () -> Void

    var body: some View {
        HStack {
            Text(count == 0 ? "Aim at a card to capture it"
                            : "\(count) card\(count == 1 ? "" : "s") ready to review")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onNext) {
                HStack(spacing: 4) {
                    Text("Next")
                    Image(systemName: "arrow.right")
                }
                .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .disabled(count == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
#endif
