import SwiftUI
import WidgetKit
import Charts

struct ActivityEntry: TimelineEntry {
    let date: Date
    let snapshot: ActivitySnapshot
    let sharedContainerAvailable: Bool
}

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        ActivityEntry(date: Date(), snapshot: ActivitySnapshot(updatedAt: Date(), days: [ActivityDay(date: Date(), steps: 6_280)], meters: 4300, goal: 8000), sharedContainerAvailable: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        // A dated entry at midnight prevents yesterday's steps being shown as today's.
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)],
                            policy: .after(min(now.addingTimeInterval(1800), midnight))))
    }
    private func entry(at date: Date) -> ActivityEntry {
        var snapshot = ActivityStorage.load()
        snapshot.goal = ActivityStorage.goal
        return ActivityEntry(date: date, snapshot: snapshot, sharedContainerAvailable: ActivityStorage.sharedDefaults != nil)
    }
}

struct ActivityWidgetView: View {
    let entry: ActivityEntry
    @Environment(\.widgetFamily) private var family
    private let green = Color(red: 0.27, green: 0.68, blue: 0.43)
    private var count: Int { entry.snapshot.steps(on: entry.date) }
    private var hasData: Bool { entry.sharedContainerAvailable && entry.snapshot.updatedAt != .distantPast }

    var body: some View {
        Group {
            if !hasData {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Step Track", systemImage: "figure.walk").font(.headline)
                    Text(entry.sharedContainerAvailable ? Copy.text("Open app to connect") : Copy.text("Open app to check widget"))
                        .font(.caption)
                }
            } else if family == .accessoryCircular {
                Gauge(value: entry.snapshot.progress(on: entry.date)) {
                    Image(systemName: "figure.walk")
                } currentValueLabel: {
                    Text(count.formatted(.number.notation(.compactName).locale(Copy.locale)))
                }.gaugeStyle(.accessoryCircular)
            } else if family == .accessoryRectangular {
                VStack(alignment: .leading) {
                    Label(Copy.format("%@ steps", Copy.number(count)), systemImage: "figure.walk").font(.headline)
                    ProgressView(value: entry.snapshot.progress(on: entry.date)).tint(green)
                    Text(Copy.format("Goal: %@ steps", Copy.number(entry.snapshot.goal))).font(.caption2)
                }
            } else {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(Copy.text("TODAY"), systemImage: "figure.walk").font(.caption2.bold()).foregroundStyle(green)
                        Text(Copy.number(count)).font(.system(size: 34, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(Copy.format("/ %@ steps", Copy.number(entry.snapshot.goal))).font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: entry.snapshot.progress(on: entry.date)).tint(green)
                        if Calendar.current.isDate(entry.snapshot.updatedAt, inSameDayAs: entry.date) {
                            Text(Copy.format("At %@", Copy.date(entry.snapshot.updatedAt, timeOnly: true))).font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text(Copy.text("Open app to update")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if family == .systemMedium {
                        Chart(entry.snapshot.days.suffix(7)) { day in
                            BarMark(x: .value(Copy.text("Day"), day.date, unit: .day), y: .value(Copy.text("Steps"), day.steps))
                                .foregroundStyle(green.gradient).cornerRadius(3)
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 115, height: 85)
                        .accessibilityLabel(Copy.text("Steps over the last 7 days"))
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .privacySensitive()
        .environment(\.locale, Copy.locale)
    }
}

@main
struct StepTrackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StepTrackActivity", provider: ActivityProvider()) { ActivityWidgetView(entry: $0) }
            .configurationDisplayName(Text(Copy.text("Today's steps")))
            .description(Text(Copy.text("Your steps, goal, and activity.")))
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
