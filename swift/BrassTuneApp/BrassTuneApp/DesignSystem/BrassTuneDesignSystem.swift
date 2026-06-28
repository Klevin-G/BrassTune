import SwiftUI

enum BTSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum BTTheme {
    static let background = Color(red: 0.027, green: 0.039, blue: 0.059)
    static let backgroundTop = Color(red: 0.039, green: 0.059, blue: 0.086)
    static let surface = Color(red: 0.067, green: 0.098, blue: 0.137)
    static let surfaceAlt = Color.white.opacity(0.055)
    static let surfaceWarm = Color(red: 0.14, green: 0.11, blue: 0.06)
    static let panelLine = Color.white.opacity(0.14)
    static let strongLine = Color(red: 0.84, green: 0.65, blue: 0.25).opacity(0.34)
    static let text = Color(red: 0.957, green: 0.973, blue: 0.984)
    static let muted = Color(red: 0.616, green: 0.671, blue: 0.733)
    static let accent = Color(red: 0.85, green: 0.65, blue: 0.25)
    static let accentSoft = Color(red: 0.94, green: 0.79, blue: 0.44)
    static let secondaryAccent = Color(red: 0.35, green: 0.79, blue: 0.70)
    static let success = Color(red: 0.42, green: 0.82, blue: 0.53)
    static let warning = Color(red: 0.90, green: 0.77, blue: 0.36)
    static let danger = Color(red: 0.89, green: 0.36, blue: 0.36)
    static let blue = Color(red: 0.46, green: 0.72, blue: 1.0)
    static let radius: CGFloat = 18
    static let radiusLarge: CGFloat = 26
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
        .background(
            LinearGradient(
                colors: [BTTheme.backgroundTop, BTTheme.background, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
    }
}

struct BTGlassPanel: ViewModifier {
    var cornerRadius: CGFloat = BTTheme.radius
    var tint: Color = BTTheme.surface
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(tint.opacity(0.72))
                    .background(.ultraThinMaterial, in: shape)
            }
            .overlay {
                shape.stroke(BTTheme.panelLine, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.32), radius: 24, x: 0, y: 14)
            .modifier(BTLiquidGlass(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

private struct BTLiquidGlass: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                interactive ? .regular.tint(tint.opacity(0.20)).interactive() : .regular.tint(tint.opacity(0.16)),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content
        }
    }
}

extension View {
    func btGlassPanel(cornerRadius: CGFloat = BTTheme.radius, tint: Color = BTTheme.surface, interactive: Bool = false) -> some View {
        modifier(BTGlassPanel(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

struct BTCard<Content: View>: View {
    let content: Content
    var tint: Color = BTTheme.surface

    init(tint: Color = BTTheme.surface, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.md) {
            content
        }
        .padding(BTSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(BTTheme.text)
        .btGlassPanel(tint: tint)
    }
}

struct BTPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var trailing: String?

    var body: some View {
        BTCard(tint: BTTheme.surfaceWarm) {
            HStack(alignment: .top, spacing: BTSpacing.lg) {
                VStack(alignment: .leading, spacing: BTSpacing.sm) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BTTheme.accentSoft)
                    Text(title)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(BTTheme.text)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(BTTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: BTSpacing.md)
                if let trailing {
                    BTStatusPill(text: trailing, tint: BTTheme.secondaryAccent)
                }
            }
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
                .foregroundStyle(BTTheme.text)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BTTheme.muted)
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
                .foregroundStyle(BTTheme.muted)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .btGlassPanel(cornerRadius: 14, tint: BTTheme.surfaceAlt, interactive: true)
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
            .overlay {
                Capsule().stroke(tint.opacity(0.28), lineWidth: 1)
            }
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
                .foregroundStyle(BTTheme.muted)
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
            .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.12))
            .background(isEnabled ? BTTheme.accentSoft : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .modifier(BTLiquidGlass(cornerRadius: BTTheme.radius, tint: BTTheme.accent, interactive: true))
    }
}

struct BTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(isEnabled ? BTTheme.text : BTTheme.muted)
            .btGlassPanel(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt, interactive: true)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTInsightTile: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint: Color = BTTheme.accent

    var body: some View {
        HStack(alignment: .top, spacing: BTSpacing.md) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: BTSpacing.xs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(BTTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BTTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .btGlassPanel(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt, interactive: true)
        .accessibilityElement(children: .combine)
    }
}
