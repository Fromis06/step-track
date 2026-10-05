import SwiftUI
import Charts
import Combine

enum TrackStyle {
    static let green = Color(red: 0.17, green: 0.55, blue: 0.36)
    static let mint = Color(red: 0.70, green: 0.91, blue: 0.48)
}

struct DashboardView: View {
    @EnvironmentObject private var activity: ActivityStore
    @State private var showSettings = false
    @State private var period = 7
    private let pulse = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var records: [ActivityDay] { Array(activity.snapshot.days.suffix(period)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    if !activity.enabled { connectionCard }
                    if let message = activity.message {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    progressCard
                    metrics
                    historyCard
                    footer
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await activity.refresh() }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .onReceive(pulse) { _ in Task { await activity.refresh() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                Task { await activity.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
                Task { await activity.refresh() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Hôm nay")
                    .font(.title2.weight(.bold)).tracking(-0.7)
            }
            Spacer(minLength: 10)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3).frame(width: 46, height: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("Cài đặt và mục tiêu")
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(ActivityStore.motionOnly ? "Bước chân từ iPhone" : "Kết nối Sức khỏe", systemImage: "heart.fill")
                .font(.headline)
            Text(ActivityStore.motionOnly
                 ? "Đọc bước chân từ cảm biến iPhone."
                 : "Đọc số bước và quãng đường của bạn.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { Task { await activity.connect() } } label: {
                HStack {
                    if activity.loading { ProgressView().tint(.white) }
                    Text(activity.loading ? "Đang kết nối…" : "Kết nối").fontWeight(.semibold)
                    Image(systemName: "arrow.up.right")
                }.frame(maxWidth: .infinity).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent).disabled(activity.loading)
        }.card()
    }

    private var progressCard: some View {
        VStack(spacing: 20) {
            HStack {
                Label("HÔM NAY", systemImage: "figure.walk")
                    .font(.caption.weight(.bold)).tracking(2)
                Spacer()
                Text("\(Int(activity.progress * 100))% mục tiêu")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            ZStack {
                Circle().stroke(.white.opacity(0.10), lineWidth: 17)
                Circle().trim(from: 0, to: activity.progress)
                    .stroke(AngularGradient(colors: [TrackStyle.green, TrackStyle.mint], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 17, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Image(systemName: "figure.walk").font(.title).foregroundStyle(TrackStyle.mint)
                    Text(activity.enabled && activity.snapshot.updatedAt != .distantPast ? activity.todaySteps.formatted() : "—")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .contentTransition(.numericText())
                    Text("bước chân").font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }.padding(30)
            }
            .frame(width: 242, height: 242).padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hôm nay \(activity.todaySteps) bước, mục tiêu \(activity.goal) bước")
            VStack(spacing: 6) {
                Text(activity.todaySteps >= activity.goal ? "Đã đạt mục tiêu" : "Mục tiêu \(activity.goal.formatted()) bước")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white).padding(24).frame(maxWidth: .infinity)
        .background(Color(red: 0.065, green: 0.19, blue: 0.145), in: RoundedRectangle(cornerRadius: 30))
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            metric("Quãng đường", symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                   value: activity.todayDistance.map { ($0 / 1000).formatted(.number.precision(.fractionLength(2))) } ?? "—",
                   unit: "km hôm nay")
            metric("Còn lại", symbol: "flag.checkered",
                   value: max(0, activity.goal - activity.todaySteps).formatted(), unit: "bước tới mục tiêu")
        }
    }

    private func metric(_ title: String, symbol: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(TrackStyle.green).font(.title3)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hoạt động").font(.headline)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis").foregroundStyle(TrackStyle.green)
            }
            if !ActivityStore.motionOnly {
                Picker("Khoảng thời gian", selection: $period) {
                    Text("7 ngày").tag(7)
                    Text("30 ngày").tag(30)
                }.pickerStyle(.segmented)
            }
            if records.isEmpty {
                ContentUnavailableView("Chưa có dữ liệu", systemImage: "figure.walk",
                                       description: Text(""))
            } else {
                Chart(records) { record in
                    BarMark(x: .value("Ngày", record.date, unit: .day), y: .value("Bước", record.steps))
                        .cornerRadius(5)
                        .foregroundStyle(Calendar.current.isDateInToday(record.date) ? TrackStyle.green : TrackStyle.green.opacity(0.3))
                        .accessibilityLabel(record.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(record.steps) bước")
                    RuleMark(y: .value("Mục tiêu", activity.goal))
                        .foregroundStyle(TrackStyle.green.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period == 7 ? 1 : 7)) {
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .frame(height: 170)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRUNG BÌNH / NGÀY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text((records.reduce(0) { $0 + $1.steps } / max(1, records.count)).formatted())
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("NGÀY ĐẠT MỤC TIÊU").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(records.filter { $0.steps >= activity.goal }.count) / \(records.count)")
                            .font(.title2.weight(.bold)).foregroundStyle(TrackStyle.green)
                    }
                }
            }
        }.card()
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label(activity.sourceName, systemImage: ActivityStore.motionOnly ? "iphone" : "heart.fill")
                .font(.caption.weight(.medium)).foregroundStyle(TrackStyle.green)
            if activity.loading {
                ProgressView("Đang cập nhật…").font(.caption)
            } else if activity.snapshot.updatedAt != .distantPast {
                Text("Cập nhật \(activity.snapshot.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if activity.enabled && !ActivityStore.motionOnly && activity.todaySteps == 0 {
                Text("Chưa có số bước · kiểm tra quyền trong Sức khỏe")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.padding(.bottom, 12)
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var activity: ActivityStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mục tiêu mỗi ngày") {
                    Text("\(activity.goal.formatted()) bước").font(.largeTitle.bold()).foregroundStyle(TrackStyle.green)
                    Stepper("Điều chỉnh 500 bước", value: $activity.goal, in: 500...50_000, step: 500)
                    HStack {
                        ForEach([6_000, 8_000, 10_000], id: \.self) { goal in
                            Button(goal.formatted()) { activity.goal = goal }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Nguồn dữ liệu") {
                    Label(activity.sourceName, systemImage: "heart.text.square")
                    if !activity.enabled {
                        Button("Kết nối dữ liệu") { Task { await activity.connect() } }.disabled(activity.loading)
                    }
                    Text(ActivityStore.motionOnly
                         ? "Bản Sideload dùng cảm biến iPhone, xem lại tối đa 7 ngày. Số liệu không bao gồm bước từ Apple Watch và có thể khác Apple Health."
                         : "App chỉ đọc số bước và quãng đường. Đổi quyền tại Sức khỏe → ảnh đại diện → Ứng dụng → Step Track. iOS không cho app biết bạn đã từ chối quyền đọc hay chưa.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Mở Cài đặt") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Section("Widget") {
                    Text(ActivityStore.motionOnly
                         ? "Bản Sideload cảm biến không kèm widget. Bản Health có widget khi được ký với quyền App Groups hợp lệ."
                         : "Nhấn giữ màn hình chính → Sửa → Thêm tiện ích → Step Track. Có cỡ nhỏ, vừa và widget màn hình khóa.")
                    if !ActivityStore.motionOnly && ActivityStorage.sharedDefaults == nil {
                        Label("Chưa truy cập được vùng dữ liệu chung. Kiểm tra chữ ký App Groups của app và widget.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text("iOS quyết định lịch cập nhật widget; số bước không thay đổi tức thì sau mỗi bước chân.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Riêng tư") {
                    Text("Không tài khoản. Không quảng cáo. Không tải dữ liệu sức khỏe lên máy chủ.")
                    if activity.enabled {
                        Button("Ngừng đọc & xóa bản lưu trong app", role: .destructive) { confirmDisconnect = true }
                    }
                }
                Section("Step Track") {
                    Text("Tham khảo Steps của Brittany Rima và cộng đồng · MIT License. Đây là bản tùy biến độc lập.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
            .confirmationDialog("Xóa bản lưu và ngừng cập nhật? Dữ liệu gốc trong Sức khỏe không bị xóa.", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Ngừng đọc & xóa bản lưu", role: .destructive) { activity.disconnect() }
            }
        }
    }
}

private extension View {
    func card() -> some View {
        padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
