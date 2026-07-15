import SwiftUI

enum AppLayout {
    static let floatingNavContentTopPadding: CGFloat = 92
    static let floatingNavFormTopInset: CGFloat = 84
}

struct ScreenScroll<Content: View>: View {
    let content: Content
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat

    init(
        topPadding: CGFloat = 12,
        bottomPadding: CGFloat = 132,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page.ignoresSafeArea())
    }
}

struct FloatingNavigationBar<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack {
                leading
                Spacer(minLength: 12)
                trailing
            }

            FloatingNavigationTitle(title: title, subtitle: subtitle)
                .padding(.horizontal, 74)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

struct GlassNavButton: View {
    let systemImage: String?
    let title: String?
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    init(
        systemImage: String? = nil,
        title: String? = nil,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = title
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 21, weight: .bold))
                }

                if let title {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(minWidth: title == nil ? 45 : 58, minHeight: 45)
            .padding(.horizontal, title == nil ? 0 : 13)
            .foregroundStyle(buttonForeground)
            .liquidGlassChrome(cornerRadius: 22.5, shadowRadius: 12, shadowY: 6)
        }
        .buttonStyle(LiquidGlassPressButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
    }

    private var buttonForeground: Color {
        if isDestructive { return Theme.danger }
        return isDisabled ? Theme.subtleText : Theme.text
    }
}

private struct FloatingNavigationTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 18.5, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: subtitle == nil ? 45 : 53)
        .frame(maxWidth: 234)
        .background(Theme.floatingTitleTint)
        .liquidGlassChrome(cornerRadius: subtitle == nil ? 22.5 : 26.5, shadowRadius: 12, shadowY: 6)
    }
}

private struct LiquidGlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .shadow(
                color: Theme.primary.opacity(configuration.isPressed ? 0.16 : 0),
                radius: configuration.isPressed ? 10 : 0,
                x: 0,
                y: configuration.isPressed ? 4 : 0
            )
            .animation(
                .interactiveSpring(response: 0.22, dampingFraction: 0.72, blendDuration: 0.08),
                value: configuration.isPressed
            )
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.subtext)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surfaceStyle(cornerRadius: 16)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.subtext)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String?
    var tint: Color = Theme.primary

    init(_ title: String, value: String, detail: String? = nil, tint: Color = Theme.primary) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtext)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.subtext)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceStyle(cornerRadius: 16)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    var tone: Tone = .neutral

    enum Tone {
        case neutral
        case success
        case warning
        case danger

        var foreground: Color {
            switch self {
            case .neutral: Theme.subtext
            case .success: Theme.success
            case .warning: Theme.warning
            case .danger: Theme.danger
            }
        }

        var background: Color {
            switch self {
            case .neutral: Theme.overlay
            case .success: Theme.successSoft
            case .warning: Theme.warningSoft
            case .danger: Theme.dangerSoft
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tone.foreground)
            .background(tone.background)
            .clipShape(Capsule())
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.dangerSoft)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct SimpleLineChart: View {
    let points: [TrendPoint]
    let value: (TrendPoint) -> Double
    var color: Color = Theme.primary

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let values = points.map(value)
                let maxValue = max(values.max() ?? 1, 1)
                let minValue = min(values.min() ?? 0, 0)
                let range = max(maxValue - minValue, 1)
                let width = proxy.size.width
                let height = proxy.size.height

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        let y = height - 8
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Theme.border.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = points.count <= 1 ? 0 : CGFloat(index) / CGFloat(points.count - 1) * width
                            let normalized = (value(point) - minValue) / range
                            let y = height - CGFloat(normalized) * (height - 16) - 8
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 120)

            HStack {
                ForEach(axisTicks) { tick in
                    Text(tick.label)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: tick.alignment)
                }
            }
        }
        .padding(12)
        .background(Theme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var axisTicks: [AxisTick] {
        guard !points.isEmpty else { return [] }
        guard points.count > 2 else {
            return points.enumerated().map { index, point in
                AxisTick(id: index, label: formatAxisDate(point.date), alignment: index == 0 ? .leading : .trailing)
            }
        }

        let middle = points.count / 2
        let last = points.count - 1
        return [
            AxisTick(id: 0, label: formatAxisDate(points[0].date), alignment: .leading),
            AxisTick(id: middle, label: formatAxisDate(points[middle].date), alignment: .center),
            AxisTick(id: last, label: formatAxisDate(points[last].date), alignment: .trailing),
        ]
    }

    private func formatAxisDate(_ raw: String) -> String {
        let hasTimeComponent = raw.contains(":") || raw.contains("T")
        if let date = Self.dateTimeFormatters.compactMap({ $0.date(from: raw) }).first
            ?? Self.isoFormatterWithFractionalSeconds.date(from: raw)
            ?? Self.isoFormatter.date(from: raw) {
            return hasTimeComponent
                ? date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                : date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
        if let date = Self.dayFormatter.date(from: raw) {
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
        return raw
    }

    private struct AxisTick: Identifiable {
        let id: Int
        let label: String
        let alignment: Alignment
    }

    private static let dateTimeFormatters: [DateFormatter] = [
        makeFormatter("yyyy-MM-dd HH:00"),
        makeFormatter("yyyy-MM-dd HH:mm"),
        makeFormatter("yyyy-MM-dd HH:mm:ss"),
    ]

    private static let dayFormatter: DateFormatter = {
        makeFormatter("yyyy-MM-dd")
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dateFormat
        return formatter
    }
}

struct ChartPlaceholder: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.subtleText)

            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity, minHeight: 164)
        .background(Theme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.subtext)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
