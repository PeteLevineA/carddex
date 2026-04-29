import SwiftUI
import CarddexCore
import CarddexCatalog

public struct BrowseTab: View {

    @State private var search = ""
    @State private var sets: [PokemonSet] = []
    @State private var results: [PokemonCard] = []
    @State private var selectedSet: PokemonSet?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if !search.isEmpty {
                    Section("Search results") {
                        ForEach(results) { card in
                            NavigationLink(value: card) {
                                CardRow(card: card)
                            }
                        }
                    }
                }
                if search.isEmpty {
                    Section("Sets") {
                        ForEach(sets) { set in
                            NavigationLink(value: set) {
                                SetRow(set: set)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, prompt: "Search the Pokémon TCG")
            .navigationTitle("Browse")
            .navigationDestination(for: PokemonSet.self) { set in
                SetDetailView(set: set)
            }
            .navigationDestination(for: PokemonCard.self) { card in
                CardDetailView(card: card)
            }
            .task { await reload() }
            .task(id: search) { await runSearch() }
        }
    }

    private func reload() async {
        sets = await CatalogStore.shared.allSets()
            .sorted { ($0.releaseDate, $0.name) > ($1.releaseDate, $1.name) }
    }

    private func runSearch() async {
        guard !search.isEmpty else { results = []; return }
        results = await CatalogStore.shared.search(name: search, limit: 30)
    }
}

private struct SetRow: View {
    let set: PokemonSet
    var body: some View {
        VStack(alignment: .leading) {
            Text(set.name).font(.headline)
            Text("\(set.series) · \(set.releaseDate) · \(set.printedTotal) cards")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CardRow: View {
    let card: PokemonCard
    var body: some View {
        HStack {
            AsyncImage(url: card.images.small.flatMap(URL.init(string:))) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                default: Color.secondary.opacity(0.1)
                }
            }
            .frame(width: 48, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading) {
                Text(card.name).font(.headline)
                Text("\(card.setName) · #\(card.number)\(card.rarity.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetDetailView: View {
    let set: PokemonSet
    @State private var cards: [PokemonCard] = []
    var body: some View {
        List(cards) { card in
            NavigationLink(value: card) { CardRow(card: card) }
        }
        .navigationTitle(set.name)
        .task {
            cards = await CatalogStore.shared.allCards()
                .filter { $0.setId == set.id }
                .sorted { lhs, rhs in
                    (Int(lhs.number) ?? 0, lhs.number) < (Int(rhs.number) ?? 0, rhs.number)
                }
        }
    }
}

private struct CardDetailView: View {
    let card: PokemonCard
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AsyncImage(url: card.images.large.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFit()
                    default: Color.secondary.opacity(0.1)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(card.name).font(.largeTitle).bold()
                LabeledContent("Set", value: card.setName)
                LabeledContent("Number", value: card.number)
                if let rarity = card.rarity { LabeledContent("Rarity", value: rarity) }
                if !card.types.isEmpty { LabeledContent("Types", value: card.types.joined(separator: ", ")) }
                if let artist = card.artist { LabeledContent("Illustrator", value: artist) }
                if let flavor = card.flavorText { Text(flavor).italic().padding(.top, 8) }
            }
            .padding()
        }
        .navigationTitle(card.name)
    }
}
