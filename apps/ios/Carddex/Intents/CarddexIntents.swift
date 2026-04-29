import AppIntents
import CarddexCore

/// `App Intents` exposed to Siri, Shortcuts, and Spotlight. These are the
/// Carddex equivalents of CollX's basic actions, plus a Carddex-specific
/// "value summary" that uses Foundation Models to phrase the answer.
public struct ScanCardIntent: AppIntent {
    public static var title: LocalizedStringResource = "Scan a card"
    public static var description = IntentDescription("Open Carddex and start a scan.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        // The app delegate handles `carddex://scan` deep links to switch tabs.
        .result()
    }
}

public struct ShowCollectionValueIntent: AppIntent {
    public static var title: LocalizedStringResource = "Show collection value"
    public static var description = IntentDescription("Summarize your Carddex collection's current value.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Real implementation reads SwiftData on the main actor and aggregates
        // prices from the cached catalog.
        return .result(dialog: "Collection summaries coming soon.")
    }
}

public struct CarddexShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanCardIntent(),
            phrases: ["Scan a card with \(.applicationName)"],
            shortTitle: "Scan a card",
            systemImageName: "viewfinder"
        )
        AppShortcut(
            intent: ShowCollectionValueIntent(),
            phrases: ["Show my \(.applicationName) collection value"],
            shortTitle: "Collection value",
            systemImageName: "dollarsign.circle"
        )
    }
}
