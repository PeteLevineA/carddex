import SwiftUI
import CarddexCore
import CarddexCatalog
import CarddexScanner

public struct SettingsTab: View {

    @AppStorage("carddex.allowCloudFallback") private var allowCloudFallback = false
    @AppStorage("carddex.savePhotosCopy")     private var savePhotosCopy = false
    @AppStorage("carddex.tcgApiKey")          private var tcgApiKey = ""
    @State private var refreshInProgress = false
    @State private var refreshSummary: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Allow cloud lookups (Tier C)", isOn: $allowCloudFallback)
                    SecureField("Pokémon TCG API key (optional)", text: $tcgApiKey)
                    Toggle("Save a copy of scans to Photos", isOn: $savePhotosCopy)
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Tier A (offline) and Tier B (Apple Intelligence) always run on-device. Tier C only fires when you enable cloud lookups.")
                }

                Section("Apple Intelligence") {
                    LabeledContent("Foundation Models") {
                        Text(FoundationModelsVerifier.isAvailable() ? "Available" : "Unavailable")
                            .foregroundStyle(FoundationModelsVerifier.isAvailable() ? .green : .secondary)
                    }
                }

                Section("Catalog") {
                    Button {
                        Task { await refreshCatalog() }
                    } label: {
                        if refreshInProgress {
                            HStack { ProgressView(); Text("Refreshing…") }
                        } else {
                            Text("Refresh Pokémon catalog")
                        }
                    }
                    if let refreshSummary {
                        Text(refreshSummary).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
                    LabeledContent("Build",   value: Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "0")
                    Link("Pokémon TCG API",     destination: URL(string: "https://pokemontcg.io")!)
                    Link("Carddex source code", destination: URL(string: "https://github.com/PeteLevineA/carddex")!)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func refreshCatalog() async {
        refreshInProgress = true
        defer { refreshInProgress = false }
        let client = PokemonTCGClient(configuration: .init(apiKey: tcgApiKey.isEmpty ? nil : tcgApiKey))
        do {
            let sets  = try await client.downloadAllSets()
            let cards = try await client.downloadAllCards()
            try await CatalogStore.shared.install(cards: cards, sets: sets)
            refreshSummary = "Cached \(cards.count) cards across \(sets.count) sets."
        } catch {
            refreshSummary = "Refresh failed: \(error.localizedDescription)"
        }
    }
}
