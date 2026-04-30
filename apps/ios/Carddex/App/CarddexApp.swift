import SwiftUI
import SwiftData
import CarddexCore
import CarddexCatalog
import CarddexUI

@main
struct CarddexApp: App {

    let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try CarddexPersistence.makeModelContainer(
                cloudKitContainerID: "iCloud.com.carddex.app"
            )
        } catch {
            // Fallback to a local-only store so the app still launches if the
            // user disabled iCloud or the entitlement is missing in dev.
            self.modelContainer = try! CarddexPersistence.makeModelContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}
