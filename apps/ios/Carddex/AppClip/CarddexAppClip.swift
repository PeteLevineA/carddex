import SwiftUI
import CarddexUI
import CarddexCatalog

/// App Clip target — a scan-only flow shareable by QR for friends to try
/// Carddex without installing the full app.
@main
struct CarddexAppClip: App {
    var body: some Scene {
        WindowGroup {
            ScanTab()
                .task { await CatalogStore.shared.bootstrap() }
        }
    }
}
