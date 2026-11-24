import SwiftUI

enum AppIcon: String, CaseIterable, Identifiable, Hashable, Sendable {
    case activity = "activity"
    case alertCircle = "alert-circle"
    case arrowUpRight = "arrow-up-right"
    case barChart2 = "bar-chart-2"
    case barChart3 = "bar-chart-3"
    case bodyBack = "body-back"
    case bodyFront = "body-front"
    case bookOpen = "book-open"
    case calendarDays = "calendar-days"
    case check = "check"
    case checkCircle2 = "check-circle-2"
    case chevronDown = "chevron-down"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case chevronUp = "chevron-up"
    case circle = "circle"
    case clock = "clock"
    case download = "download"
    case droplets = "droplets"
    case dumbbell = "dumbbell"
    case flame = "flame"
    case footprints = "footprints"
    case globe = "globe"
    case heart = "heart"
    case heartPulse = "heart-pulse"
    case home = "home"
    case layers = "layers"
    case lock = "lock"
    case minus = "minus"
    case moon = "moon"
    case palette = "palette"
    case pause = "pause"
    case pencil = "pencil"
    case personStanding = "person-standing"
    case play = "play"
    case plus = "plus"
    case refreshCw = "refresh-cw"
    case rotate3d = "rotate-3d"
    case rotateCcw = "rotate-ccw"
    case route = "route"
    case scale = "scale"
    case search = "search"
    case settings = "settings"
    case shieldCheck = "shield-check"
    case slidersHorizontal = "sliders-horizontal"
    case smartphone = "smartphone"
    case sparkles = "sparkles"
    case sun = "sun"
    case target = "target"
    case timer = "timer"
    case trash2 = "trash-2"
    case trendingDown = "trending-down"
    case trendingUp = "trending-up"
    case trophy = "trophy"
    case upload = "upload"
    case user = "user"
    case utensils = "utensils"
    case x = "x"
    case zap = "zap"

    var id: String { rawValue }
}

struct SvgIconView: View {
    let icon: AppIcon
    var size: CGFloat = 20
    var color: Color = .primary

    init(icon: AppIcon, size: CGFloat = 20, color: Color = .primary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    init(_ icon: AppIcon, size: CGFloat = 20, color: Color = .primary) {
        self.icon = icon
        self.size = size
        self.color = color
    }

    var body: some View {
        Image(icon.rawValue)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
