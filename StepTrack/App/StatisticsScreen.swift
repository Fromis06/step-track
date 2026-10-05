import SwiftUI

struct StatisticsScreen: View {
    @EnvironmentObject private var activity: ActivityStore
    @AppStorage("appLanguage", store: ActivityStorage.defaults) private var language = "vi"
    @State private var mode = "month"
    @State private var anchor = Date()
    @State private var selectedDay = HistoryCalendar.key(for: Date())
    private var calendar: Calendar { HistoryCalendar.calendar }
    private var year: Int { calendar.component(.year, from: anchor) }
    private var month: Int { calendar.component(.month, from: anchor) }
    private var records: [HistoricalDay] { activity.history.records(year: year, month: mode == "month" ? month : nil) }
    private var total: Int { records.reduce(0) { $0 + $1.steps } }
    private var months: [Date] {
        (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }
    private var periodTitle: String {
        if mode == "year" { return String(year) }
        return anchor.formatted(.dateTime.month(.wide).year().locale(Copy.locale))
    }
    private var canGoForward: Bool {
        calendar.compare(anchor, to: Date(), toGranularity: mode == "month" ? .month : .year) == .orderedAscending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(Copy.text("Statistics")).font(.largeTitle.bold()).tracking(-1)
                    Picker(Copy.text("Period"), selection: $mode) {
                        Text(Copy.text("Month")).tag("month")
                        Text(Copy.text("Year")).tag("year")
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("statisticsPeriod")
                    calendarCard
                    if mode == "month" { dayDetail }
                    if let message = activity.historyMessage {
                        Text(Copy.text(message)).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .contentMargins(.bottom, 86, for: .scrollContent)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await activity.refresh() }
            .environment(\.locale, Locale(identifier: language))
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(periodTitle).font(.headline).accessibilityIdentifier("statisticsHeading")
                    HStack(spacing: 4) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 34) }
                            .disabled(year <= 2000 && (mode == "year" || month == 1))
                            .accessibilityLabel(Copy.text("Previous period")).accessibilityIdentifier("previousPeriod")
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 34) }
                            .disabled(!canGoForward)
                            .accessibilityLabel(Copy.text("Next period")).accessibilityIdentifier("nextPeriod")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Copy.text("Total steps")).font(.caption).foregroundStyle(.secondary)
                    Text(Copy.number(total))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(TrackStyle.green)
                        .accessibilityIdentifier("periodTotal")
                }
            }
            if mode == "month" {
                MonthActivityGrid(month: anchor, history: activity.history, selected: selectedDay) { date in
                    selectedDay = HistoryCalendar.key(for: date)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                    ForEach(months, id: \.self) { date in
                        Button {
                            anchor = date
                            selectedDay = HistoryCalendar.key(for: date)
                            mode = "month"
                        } label: {
                            MiniMonthView(month: date, history: activity.history)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(.dateTime.month(.wide).year().locale(Copy.locale)))
                        .accessibilityIdentifier("month-\(calendar.component(.month, from: date))")
                    }
                }.accessibilityIdentifier("yearGrid")
            }
            HStack(spacing: 14) {
                legend("No data", fill: Color.clear, outlined: true)
                legend("Below goal", fill: Color(.systemGray4))
                legend("Goal reached", fill: TrackStyle.green)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }.card()
    }

    private var dayDetail: some View {
        let day = activity.history.days[selectedDay]
        let date = HistoryCalendar.date(for: selectedDay) ?? anchor
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(date.formatted(.dateTime.day().month(.wide).year().locale(Copy.locale)))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if day?.reachedGoal == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(TrackStyle.green)
                        .accessibilityLabel(Copy.text("Goal reached"))
                }
            }
            if let day {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.format("%@ steps", Copy.number(day.steps))).font(.title2.bold())
                    Spacer()
                    Text(day.goal.map { Copy.format("Goal: %@", Copy.number($0)) } ?? Copy.text("Goal not recorded"))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("selectedDayGoal")
                }
                if !day.complete && selectedDay != HistoryCalendar.key(for: Date()) {
                    Text(Copy.text("Partial day")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(Copy.text("No data yet")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).card()
        .accessibilityIdentifier("selectedDayDetail")
    }

    private func legend(_ title: String, fill: Color, outlined: Bool = false) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(outlined ? 0.35 : 0), lineWidth: 1))
            Text(Copy.text(title)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func move(_ direction: Int) {
        guard let next = calendar.date(byAdding: mode == "month" ? .month : .year, value: direction, to: anchor) else { return }
        anchor = next
        if let start = calendar.dateInterval(of: .month, for: next)?.start {
            selectedDay = HistoryCalendar.key(for: start)
        }
    }
}

private struct MonthActivityGrid: View {
    let month: Date
    let history: ActivityHistory
    let selected: String
    let select: (Date) -> Void
    private var weekdays: [String] {
        let formatter = DateFormatter()
        formatter.locale = Copy.locale
        let labels = formatter.shortStandaloneWeekdaySymbols ?? []
        return labels.isEmpty ? [] : Array(labels.dropFirst()) + [labels[0]]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, label in
                    Text(label).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(HistoryCalendar.monthCells(containing: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = HistoryCalendar.key(for: date)
                        let day = history.days[key]
                        let future = key > HistoryCalendar.key(for: Date())
                        Button { select(date) } label: {
                            ActivityCell(day: day, future: future)
                                .overlay {
                                    Text(String(HistoryCalendar.calendar.component(.day, from: date)))
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(day?.reachedGoal == true ? .white : Color.primary.opacity(future ? 0.25 : 0.75))
                                }
                                .overlay {
                                    if key == selected { RoundedRectangle(cornerRadius: 7).strokeBorder(TrackStyle.green, lineWidth: 2).padding(-2) }
                                }
                        }
                        .buttonStyle(.plain).disabled(future)
                        .accessibilityIdentifier("day-\(key)")
                        .accessibilityLabel(date.formatted(.dateTime.day().month(.wide).locale(Copy.locale)))
                        .accessibilityValue(day.map { Copy.format("%@ steps", Copy.number($0.steps)) + ", " + Copy.text($0.reachedGoal ? "Goal reached" : ($0.goal == nil ? "Goal not recorded" : "Below goal")) } ?? Copy.text("No data"))
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

private struct MiniMonthView: View {
    let month: Date
    let history: ActivityHistory
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(month.formatted(.dateTime.month(.abbreviated).locale(Copy.locale)))
                .font(.caption.weight(.semibold)).foregroundStyle(.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(Array(HistoryCalendar.monthCells(containing: month).enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = HistoryCalendar.key(for: date)
                        ActivityCell(day: history.days[key], future: key > HistoryCalendar.key(for: Date()), radius: 2)
                    } else {
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }.frame(maxWidth: 88)
        }
        .accessibilityElement(children: .ignore)
    }
}

private struct ActivityCell: View {
    let day: HistoricalDay?
    let future: Bool
    var radius: CGFloat = 7
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(day.map { $0.reachedGoal ? TrackStyle.green : Color(.systemGray4) } ?? Color(.tertiarySystemGroupedBackground))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.secondary.opacity(day == nil && !future ? 0.22 : 0), lineWidth: 0.75))
            .opacity(future ? 0.3 : 1)
            .aspectRatio(1, contentMode: .fit)
    }
}
