import WidgetKit
import SwiftUI
import CarddexCore
import CarddexCatalog

/// "Card of the day" widget — pulls a deterministic card from the bundled
/// holofoil catalog so it works fully offline.
struct CardOfTheDayProvider: TimelineProvider {

    func placeholder(in context: Context) -> CardOfTheDayEntry {
        CardOfTheDayEntry(date: .now, name: "Aurora Pikachu", set: "Neon Meadow")
    }

    func getSnapshot(in context: Context, completion: @escaping (CardOfTheDayEntry) -> ()) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CardOfTheDayEntry>) -> ()) {
        Task {
            await CatalogStore.shared.bootstrap()
            let cards = await CatalogStore.shared.allHolofoilCards()
            guard !cards.isEmpty else {
                let entry = placeholder(in: context)
                let next = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
                completion(Timeline(entries: [entry], policy: .after(next)))
                return
            }
            let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
            let pick = cards[(dayOfYear) % cards.count]
            let entry = CardOfTheDayEntry(date: .now, name: pick.name, set: pick.set ?? "")
            // Refresh once per day.
            let next = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct CardOfTheDayEntry: TimelineEntry {
    let date: Date
    let name: String
    let set: String
}

struct CardOfTheDayWidgetView: View {
    let entry: CardOfTheDayEntry
    var body: some View {
        VStack(alignment: .leading) {
            Text("Card of the day").font(.caption).foregroundStyle(.secondary)
            Text(entry.name).font(.headline)
            Text(entry.set).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct CarddexWidgets: WidgetBundle {
    var body: some Widget {
        CardOfTheDayWidget()
    }
}

struct CardOfTheDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CardOfTheDay", provider: CardOfTheDayProvider()) { entry in
            CardOfTheDayWidgetView(entry: entry)
        }
        .configurationDisplayName("Card of the day")
        .description("A different card from your Carddex catalog every day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
