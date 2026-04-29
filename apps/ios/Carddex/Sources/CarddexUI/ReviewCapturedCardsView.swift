import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog

#if canImport(UIKit)
import UIKit

/// Detailed review screen for cards the user has captured but not yet saved.
/// Each captured card gets its own large row with editable name, set, number,
/// type, rarity, condition, variant, and quantity. **Save** persists the
/// HEIC crops to disk and inserts a `CollectionItem` + linked `Scan` for each
/// card in one batch, then dismisses back to the camera.
public struct ReviewCapturedCardsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var capturedCards: [CapturedCard]
    @State private var isSaving = false
    @State private var saveError: String?

    public init(capturedCards: Binding<[CapturedCard]>) {
        self._capturedCards = capturedCards
    }

    public var body: some View {
        List {
            ForEach($capturedCards) { $card in
                CapturedCardEditorRow(card: $card)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            .onDelete(perform: removeCards)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Review \(capturedCards.count) card\(capturedCards.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await saveAll() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").bold()
                    }
                }
                .disabled(isSaving || capturedCards.isEmpty)
            }
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func removeCards(at offsets: IndexSet) {
        capturedCards.remove(atOffsets: offsets)
    }

    @MainActor
    private func saveAll() async {
        isSaving = true
        defer { isSaving = false }
        do {
            for card in capturedCards {
                try persist(card)
            }
            try modelContext.save()
            capturedCards.removeAll()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Writes the cropped HEIC to `Application Support/scans/` and inserts the
    /// linked `CollectionItem` + `Scan` records.
    private func persist(_ card: CapturedCard) throws {
        let fileName = "\(card.id.uuidString).heic"
        let url = CarddexStorage.scansDirectory.appendingPathComponent(fileName)
        try card.imageData.write(to: url, options: [.atomic])
        let relativePath = CarddexStorage.relativePath(for: fileName)

        let draft = card.draft
        let item = CollectionItem(
            cardId: card.scanResult.bestCardId ?? "\(draft.setId)-\(draft.number)",
            setId: draft.setId,
            number: draft.number,
            quantity: draft.quantity,
            condition: draft.condition,
            variant: draft.variant,
            language: draft.language,
            notes: draft.notes
        )

        let scan = Scan(croppedImagePath: relativePath)
        scan.guessedCardId = card.scanResult.bestCardId
        scan.guessedSetId  = card.scanResult.bestSetId
        scan.guessedNumber = card.scanResult.bestNumber
        scan.confidence    = card.scanResult.confidence
        scan.ocrText       = card.scanResult.ocrText
        scan.tier          = card.scanResult.tier
        scan.alternates    = card.scanResult.alternates
        scan.userConfirmed = true
        scan.collectionItem = item

        modelContext.insert(item)
        modelContext.insert(scan)
    }
}

// MARK: - Editor row

struct CapturedCardEditorRow: View {
    @Binding var card: CapturedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let thumb = card.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 134)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Captured photo of \(card.draft.name)")
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 96, height: 134)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Card name", text: $card.draft.name)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("Number", text: $card.draft.number)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        TextField("Set ID", text: $card.draft.setId)
                            .textFieldStyle(.roundedBorder)
                    }
                    TextField("Set name", text: $card.draft.setName)
                        .textFieldStyle(.roundedBorder)
                    Text(String(format: "%.0f%% confidence · Tier %@",
                                card.scanResult.confidence * 100, card.scanResult.tier.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Group {
                LabeledTextField(title: "Card type", text: $card.draft.types,
                                 prompt: "e.g. Fire, Water")
                LabeledTextField(title: "Supertype", text: $card.draft.supertype,
                                 prompt: "Pokémon / Trainer / Energy")
                LabeledTextField(title: "Rarity", text: $card.draft.rarity,
                                 prompt: "Common, Rare Holo, …")
            }

            HStack {
                Stepper("Qty: \(card.draft.quantity)",
                        value: $card.draft.quantity, in: 1...999)
                    .frame(maxWidth: 160)
                Spacer()
                Picker("Condition", selection: $card.draft.condition) {
                    ForEach(CollectionItem.Condition.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Picker("Variant", selection: $card.draft.variant) {
                    ForEach(CollectionItem.Variant.allCases, id: \.self) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Picker("Language", selection: $card.draft.language) {
                    Text("English").tag("en")
                    Text("Japanese").tag("ja")
                    Text("Other").tag("other")
                }
                .pickerStyle(.menu)
            }

            TextField("Notes", text: $card.draft.notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }
}

private struct LabeledTextField: View {
    let title: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
#endif
