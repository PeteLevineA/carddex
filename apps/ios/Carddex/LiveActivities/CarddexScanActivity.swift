import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity for an active scanning session: shows running totals in the
/// Dynamic Island while the user rips a pack.
public struct CarddexScanActivityAttributes: ActivityAttributes {
    public typealias ContentState = State

    public struct State: Codable, Hashable {
        public var scannedCount: Int
        public var lastCardName: String
        public init(scannedCount: Int, lastCardName: String) {
            self.scannedCount = scannedCount
            self.lastCardName = lastCardName
        }
    }

    public var sessionTitle: String
    public init(sessionTitle: String) { self.sessionTitle = sessionTitle }
}

@available(iOS 16.1, *)
public struct CarddexScanActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CarddexScanActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text(context.attributes.sessionTitle).font(.headline)
                Text("\(context.state.scannedCount) cards · last: \(context.state.lastCardName)")
                    .font(.caption)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading)  { Text("Carddex").font(.caption) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.scannedCount)") }
                DynamicIslandExpandedRegion(.bottom)   { Text(context.state.lastCardName) }
            } compactLeading: {
                Image(systemName: "viewfinder")
            } compactTrailing: {
                Text("\(context.state.scannedCount)")
            } minimal: {
                Image(systemName: "viewfinder")
            }
        }
    }
}
