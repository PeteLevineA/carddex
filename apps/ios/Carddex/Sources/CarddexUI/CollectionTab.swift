import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog

public struct CollectionTab: View {

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionItem.updatedAt, order: .reverse) private var items: [CollectionItem]
    @State private var search = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "rectangle.stack",
                        description: Text("Use the Scan tab to add your first card.")
                    )
                }
                ForEach(filtered) { item in
                    NavigationLink(value: item) {
                        CollectionRow(item: item)
                    }
                }
                .onDelete(perform: delete)
            }
            .searchable(text: $search, prompt: "Search by set or number")
            .navigationTitle("Collection")
            .navigationDestination(for: CollectionItem.self) { item in
                CollectionDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: exportCSV(), preview: SharePreview("Carddex export"))
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var filtered: [CollectionItem] {
        guard !search.isEmpty else { return items }
        let s = search.lowercased()
        return items.filter {
            $0.setId.lowercased().contains(s) || $0.number.lowercased().contains(s) || $0.cardId.lowercased().contains(s)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filtered[index]) }
        try? modelContext.save()
    }

    private func exportCSV() -> URL {
        let header = "cardId,setId,number,quantity,condition,variant,language,addedAt\n"
        let rows = items.map { i in
            "\(i.cardId),\(i.setId),\(i.number),\(i.quantity),\(i.conditionRaw),\(i.variantRaw),\(i.languageRaw),\(ISO8601DateFormatter().string(from: i.addedAt))"
        }.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("carddex.csv")
        try? (header + rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct CollectionRow: View {
    let item: CollectionItem
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(item.setId) · #\(item.number)").font(.headline)
                Text("Qty \(item.quantity) · \(item.conditionRaw) · \(item.variantRaw)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct CollectionDetailView: View {
    @Bindable var item: CollectionItem

    var body: some View {
        Form {
            Section("Identity") {
                LabeledContent("Card ID", value: item.cardId)
                LabeledContent("Set", value: item.setId)
                LabeledContent("Number", value: item.number)
            }
            Section("Inventory") {
                Stepper("Quantity: \(item.quantity)", value: $item.quantity, in: 0...999)
                Picker("Condition", selection: $item.conditionRaw) {
                    ForEach(CollectionItem.Condition.allCases, id: \.rawValue) { c in
                        Text(c.rawValue).tag(c.rawValue)
                    }
                }
                Picker("Variant", selection: $item.variantRaw) {
                    ForEach(CollectionItem.Variant.allCases, id: \.rawValue) { v in
                        Text(v.rawValue).tag(v.rawValue)
                    }
                }
                TextField("Notes", text: $item.notes, axis: .vertical)
            }
            if !item.scans.isEmpty {
                Section("Scans") {
                    ForEach(item.scans) { scan in
                        VStack(alignment: .leading) {
                            Text(scan.createdAt, style: .date)
                            Text("Tier \(scan.tierRaw) · \(Int(scan.confidence * 100))% · \(scan.userConfirmed ? "confirmed" : "auto")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(item.setId) · #\(item.number)")
        .onChange(of: item.quantity) { _, _ in item.updatedAt = Date(); try? item.modelContext?.save() }
    }
}
