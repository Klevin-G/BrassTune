import SwiftUI
import UIKit

/// Makes the localization intent of design-system copy explicit. String
/// literals are catalog keys; dynamic or user-authored values must opt into
/// `.verbatim(...)` at the call site. This prevents `Text(variable)` from
/// silently bypassing the selected in-app language.
enum BTCopy: ExpressibleByStringLiteral, Equatable, Hashable {
    case localized(String)
    case verbatim(String)

    init(stringLiteral value: String) {
        self = .localized(value)
    }

    var resolved: String {
        switch self {
        case .localized(let key): return NativeLocalization.string(key)
        case .verbatim(let value): return value
        }
    }
}

private extension Text {
    init(_ copy: BTCopy) {
        self.init(verbatim: copy.resolved)
    }
}

enum BTSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum BTTheme {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let backgroundTop = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceAlt = Color(uiColor: .tertiarySystemGroupedBackground)
    static let surfaceWarm = adaptive(
        light: UIColor(red: 1.000, green: 0.980, blue: 0.941, alpha: 1),
        dark: UIColor(red: 0.133, green: 0.106, blue: 0.059, alpha: 1)
    )
    static let panelLine = Color(uiColor: .separator).opacity(0.55)
    static let strongLine = adaptive(
        light: UIColor(red: 0.553, green: 0.435, blue: 0.200, alpha: 0.34),
        dark: UIColor(red: 0.847, green: 0.647, blue: 0.247, alpha: 0.40)
    )
    static let text = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let accent = adaptive(
        light: UIColor(red: 0.553, green: 0.435, blue: 0.200, alpha: 1),
        dark: UIColor(red: 0.847, green: 0.647, blue: 0.247, alpha: 1)
    )
    static let accentSoft = adaptive(
        light: UIColor(red: 0.553, green: 0.435, blue: 0.200, alpha: 1),
        dark: UIColor(red: 0.941, green: 0.788, blue: 0.439, alpha: 1)
    )
    static let onAccent = adaptive(
        light: .white,
        dark: UIColor(red: 0.08, green: 0.07, blue: 0.05, alpha: 1)
    )
    static let secondaryAccent = Color(uiColor: .systemTeal)
    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)
    static let blue = Color(uiColor: .systemBlue)
    static let sharp = Color(uiColor: .systemOrange)
    static let flat = Color(uiColor: .systemBlue)
    static let unstable = Color(uiColor: .secondaryLabel)
    static let radius: CGFloat = 18
    static let radiusLarge: CGFloat = 26

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct BTScreen<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            // Regular VStack (not Lazy): these are short app screens, not long
            // lists. LazyVStack left below-the-fold controls (e.g. the tuner's
            // "Start listening" button) unrendered and unreachable to
            // VoiceOver/UI tests until scrolled into view.
            VStack(alignment: .leading, spacing: BTSpacing.lg) {
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

struct BTContentSurface: ViewModifier {
    var cornerRadius: CGFloat = BTTheme.radius
    var tint: Color = BTTheme.surface
    var interactive = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(tint)
            }
            .overlay {
                shape.stroke(BTTheme.panelLine, lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(interactive ? 0.07 : 0.04),
                radius: interactive ? 4 : 2,
                x: 0,
                y: 1
            )
    }
}

private struct BrassGlassModifier<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape
    var tint: Color?
    var interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                GlassEffectContainer {
                    content.glassEffect(
                        interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                        in: shape
                    )
                }
            } else {
                GlassEffectContainer {
                    content.glassEffect(
                        interactive ? .regular.interactive() : .regular,
                        in: shape
                    )
                }
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(BTTheme.panelLine, lineWidth: 1)
                }
                .clipShape(shape)
        }
    }
}

extension View {
    func btMinimumInteractiveSize(alignment: Alignment = .center) -> some View {
        frame(minWidth: 44, minHeight: 44, alignment: alignment)
            .contentShape(Rectangle())
    }

    func btContentSurface(
        cornerRadius: CGFloat = BTTheme.radius,
        tint: Color = BTTheme.surface,
        interactive: Bool = false
    ) -> some View {
        modifier(BTContentSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    /// Compatibility spelling for existing call sites. This is intentionally an
    /// opaque content surface now; Liquid Glass is reserved for floating chrome.
    func btGlassPanel(cornerRadius: CGFloat = BTTheme.radius, tint: Color = BTTheme.surface, interactive: Bool = false) -> some View {
        btContentSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive)
    }

    func brassGlass<GlassShape: Shape>(
        in shape: GlassShape,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(BrassGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    func brassGlass(
        cornerRadius: CGFloat = BTTheme.radiusLarge,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        brassGlass(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint,
            interactive: interactive
        )
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
        .btContentSurface(tint: tint)
    }
}

struct BTPageHeader: View {
    let eyebrow: BTCopy
    let title: BTCopy
    let subtitle: BTCopy
    var trailing: BTCopy?

    var body: some View {
        HStack(alignment: .top, spacing: BTSpacing.lg) {
            VStack(alignment: .leading, spacing: BTSpacing.sm) {
                Text(verbatim: eyebrow.resolved.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BTTheme.accentSoft)
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(BTTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(.horizontal, BTSpacing.xs)
    }
}

struct BTSectionHeader: View {
    let title: BTCopy
    var subtitle: BTCopy?

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
    let title: BTCopy
    let value: BTCopy
    var detail: BTCopy?
    var tint: Color = BTTheme.accent
    var interactive: Bool = false

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
        .btContentSurface(cornerRadius: 14, tint: BTTheme.surfaceAlt, interactive: interactive)
        .accessibilityElement(children: .combine)
    }
}

struct BTStatusPill: View {
    let text: BTCopy
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
            .accessibilityLabel(Text(text))
    }
}

struct BTEmptyState: View {
    let title: BTCopy
    let message: BTCopy
    var systemImage: String = "music.note"

    var body: some View {
        BTCard {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.headline)
            .foregroundStyle(BTTheme.accent)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BTTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BrassGlassButtonStyle: PrimitiveButtonStyle {
    var prominent: Bool
    var tint: Color?

    init(prominent: Bool = true, tint: Color? = BTTheme.accent) {
        self.prominent = prominent
        self.tint = tint
    }

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                button(configuration)
                    .buttonStyle(.glassProminent)
                    .tint(tint)
            } else {
                button(configuration)
                    .buttonStyle(.glass)
                    .tint(tint)
            }
        } else {
            if prominent {
                button(configuration)
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
            } else {
                button(configuration)
                    .buttonStyle(.bordered)
                    .tint(tint)
            }
        }
    }

    private func button(_ configuration: Configuration) -> some View {
        Button(role: configuration.role) {
            configuration.trigger()
        } label: {
            configuration.label
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .padding(.vertical, BTSpacing.xs)
                .contentShape(Rectangle())
        }
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: BTTheme.radius))
    }
}

struct BTPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous)
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(isEnabled ? BTTheme.onAccent : BTTheme.muted)
            .background(shape.fill(isEnabled ? BTTheme.accent : BTTheme.surfaceAlt))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BTTheme.radius, style: .continuous)
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, BTSpacing.md)
            .foregroundStyle(isEnabled ? BTTheme.text : BTTheme.muted)
            .background(shape.fill(BTTheme.surfaceAlt))
            .overlay {
                shape.stroke(BTTheme.panelLine, lineWidth: 1)
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct BTInsightTile: View {
    let title: BTCopy
    let detail: BTCopy
    let systemImage: String
    var tint: Color = BTTheme.accent
    var interactive: Bool = false

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
        .btContentSurface(cornerRadius: BTTheme.radius, tint: BTTheme.surfaceAlt, interactive: interactive)
        .accessibilityElement(children: .combine)
    }
}
