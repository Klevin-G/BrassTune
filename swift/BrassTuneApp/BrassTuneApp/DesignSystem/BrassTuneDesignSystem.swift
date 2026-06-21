import SwiftUI

enum BTSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

private struct BTPaletteKey: EnvironmentKey {
    static let defaultValue = BTGeneratedThemeTokens.palette(for: .brassNight, systemScheme: .dark, highContrast: false)
}

extension EnvironmentValues {
    var btPalette: BTThemePalette {
        get { self[BTPaletteKey.self] }
        set { self[BTPaletteKey.self] = newValue }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    private static let storageKey = "brasstune.native.theme"
    @AppStorage("brasstune.native.theme") private var storedTheme = BTThemeID.system.rawValue
    @Published private(set) var selectedTheme: BTThemeID = .system

    init() {
        let rawValue = UserDefaults.standard.string(forKey: Self.storageKey) ?? BTThemeID.system.rawValue
        selectedTheme = BTThemeID(rawValue: rawValue) ?? .system
    }

    func select(_ theme: BTThemeID) {
        selectedTheme = theme
        storedTheme = theme.rawValue
    }
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

struct BTThemeHost<Content: View>: View {
    @ObservedObject var manager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let content: Content

    init(manager: ThemeManager, @ViewBuilder content: () -> Content) {
        self.manager = manager
        self.content = content()
    }

    var body: some View {
        let palette = BTGeneratedThemeTokens.palette(
            for: manager.selectedTheme,
            systemScheme: colorScheme,
            highContrast: colorSchemeContrast == .increased
        )
        content
            .environment(\.btPalette, palette)
            .environmentObject(manager)
            .preferredColorScheme(palette.colorScheme)
            .tint(palette.accent)
    }
}

struct BTThemeSelector: View {
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        Picker("Theme", selection: Binding(
            get: { themeManager.selectedTheme },
            set: { themeManager.select($0) }
        )) {
            ForEach(BTThemeID.allCases) { theme in
                Text(theme.title).tag(theme)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("theme.selector")
    }
}

struct BTScreen<Content: View>: View {
    @Environment(\.btPalette) private var palette
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
        .background(palette.background.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 132, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 28)
        }
    }
}

struct BTCard<Content: View>: View {
    @Environment(\.btPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        .btGlassSurface(palette: palette, reduceTransparency: reduceTransparency)
    }
}

struct BTSectionHeader: View {
    @Environment(\.btPalette) private var palette
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct BTMetricTile: View {
    @Environment(\.btPalette) private var palette
    let title: String
    let value: String
    var detail: String?
    var tint: Color = BTTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: BTSpacing.xs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.mutedText)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(palette.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BTSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: BTGeneratedThemeTokens.radiusSmall, style: .continuous))
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
    @Environment(\.btPalette) private var palette
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
                .foregroundStyle(palette.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.btPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(.white)
            .background(isEnabled ? palette.accent : Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: BTGeneratedThemeTokens.radiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.btPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(isEnabled ? palette.accent : .secondary)
            .background(palette.surfaceAlt)
            .clipShape(RoundedRectangle(cornerRadius: BTGeneratedThemeTokens.radiusSmall, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTBentoGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BTSpacing.lg) {
                content
            }
            LazyVGrid(columns: [GridItem(.flexible())], spacing: BTSpacing.lg) {
                content
            }
        }
    }
}

struct BTBentoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        BTCard { content }
    }
}

struct BTHeroCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        BTCard {
            content
        }
        .accessibilityIdentifier("bento.hero")
    }
}

struct BTMetricCard: View {
    let title: String
    let value: String
    let detail: String?
    var tint: Color = BTTheme.accent

    var body: some View {
        BTBentoCard {
            BTMetricTile(title: title, value: value, detail: detail, tint: tint)
        }
    }
}

struct BTQuickActionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        BTCard {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
    }
}

struct BTStatusCard: View {
    let title: String
    let message: String
    let status: String
    var tint: Color = BTTheme.accent

    var body: some View {
        BTCard {
            HStack(alignment: .top) {
                BTSectionHeader(title: title, subtitle: message)
                Spacer()
                BTStatusPill(text: status, tint: tint)
            }
        }
    }
}

struct BTChartCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        BTCard {
            BTSectionHeader(title: title)
            content
        }
    }
}

struct BTGlassToolbar<Content: View>: View {
    @Environment(\.btPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: BTSpacing.sm) {
            content
        }
        .padding(BTSpacing.sm)
        .btGlassSurface(palette: palette, reduceTransparency: reduceTransparency, cornerRadius: BTGeneratedThemeTokens.radiusExtraLarge)
    }
}

struct BTGlassCapsule<Content: View>: View {
    @Environment(\.btPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: BTSpacing.sm) {
            content
        }
        .padding(.horizontal, BTSpacing.md)
        .padding(.vertical, BTSpacing.sm)
        .btGlassSurface(palette: palette, reduceTransparency: reduceTransparency, cornerRadius: BTGeneratedThemeTokens.radiusExtraLarge)
    }
}

struct BTAdaptiveSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        BTBentoGrid { content }
    }
}

private extension View {
    @ViewBuilder
    func btGlassSurface(
        palette: BTThemePalette,
        reduceTransparency: Bool,
        cornerRadius: CGFloat = BTGeneratedThemeTokens.radiusMedium
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background {
                if reduceTransparency || palette.glassStyle == .solid {
                    shape.fill(palette.surface)
                } else {
                    shape.fill(palette.glassTint.opacity(palette.glassOpacity))
                }
            }
            .clipShape(shape)
            .overlay {
                shape.stroke(palette.border, lineWidth: 1)
            }
            .modifier(BTLiquidGlassModifier(
                isEnabled: !reduceTransparency && palette.glassStyle != .solid,
                cornerRadius: cornerRadius,
                tint: palette.glassTint
            ))
    }
}

private struct BTLiquidGlassModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *), isEnabled {
                content
                    .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
            }
        #else
            content
        #endif
    }
}
