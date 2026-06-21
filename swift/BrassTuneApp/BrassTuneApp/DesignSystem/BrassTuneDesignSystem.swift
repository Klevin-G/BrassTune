import SwiftUI

enum BTSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum BTTheme {
    static let background = Color(red: 0.95, green: 0.97, blue: 0.98)
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.90, green: 0.94, blue: 0.95)
    static let accent = Color(red: 0.07, green: 0.40, blue: 0.43)
    static let secondaryAccent = Color(red: 0.67, green: 0.31, blue: 0.22)
    static let success = Color(red: 0.12, green: 0.48, blue: 0.30)
    static let warning = Color(red: 0.73, green: 0.49, blue: 0.10)
    static let danger = Color(red: 0.74, green: 0.18, blue: 0.20)
    static let radius: CGFloat = 8
}

struct BTScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BTSpacing.lg) {
                content
            }
            .padding(BTSpacing.lg)
            .safeAreaPadding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BTTheme.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
    }
}

struct BTCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            content
        }
        .padding(BTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BTTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

struct BTSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BTMetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = BTTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BTTheme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct BTStatusPill: View {
    let text: String
    var tint: Color = BTTheme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, BTSpacing.sm)
            .padding(.vertical, BTSpacing.xs)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(text)
    }
}

struct BTEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "music.note"

    var body: some View {
        BTCard {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(BTTheme.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(.white)
            .background(isEnabled ? BTTheme.accent : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(isEnabled ? BTTheme.accent : .secondary)
            .background(BTTheme.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
