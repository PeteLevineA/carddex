import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog
import CarddexScanner
import CarddexHolofoil

/// Top-level tab view that hosts every screen in the iOS app. The app target
/// instantiates this with a configured `ModelContainer` and `CatalogStore`.
public struct RootTabView: View {

    @State private var selection: Tab = .scan

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            ScanTab()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(Tab.scan)

            CollectionTab()
                .tabItem { Label("Collection", systemImage: "rectangle.stack") }
                .tag(Tab.collection)

            BrowseTab()
                .tabItem { Label("Browse", systemImage: "magnifyingglass") }
                .tag(Tab.browse)

            HolofoilTab()
                .tabItem { Label("Holofoil", systemImage: "sparkles") }
                .tag(Tab.holofoil)

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .task { await CatalogStore.shared.bootstrap() }
    }

    public enum Tab: Hashable { case scan, collection, browse, holofoil, settings }
}
