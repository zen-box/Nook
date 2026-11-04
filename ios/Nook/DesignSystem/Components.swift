import SwiftUI

// MARK: - Card

struct CardStyle: ViewModifier {
    let padding: CGFloat
    let fill: AnyShapeStyle

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.cardHighlight, Theme.border], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .shadow(color: Theme.shadowNear, radius: 2, x: 0, y: 1)
            .shadow(color: Theme.shadow, radius: 18, x: 0, y: 8)
    }
}

extension View {
    /// The white rounded card used across the app: hairline border and a very soft shadow.
    func card(padding: CGFloat = Metrics.cardPadding) -> some View {
        modifier(CardStyle(padding: padding, fill: AnyShapeStyle(Theme.surface)))
    }

    /// A card with a tinted or gradient background.
    func card<S: ShapeStyle>(padding: CGFloat = Metrics.cardPadding, fill: S) -> some View {
        modifier(CardStyle(padding: padding, fill: AnyShapeStyle(fill)))
    }
}

// MARK: - Buttons

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// The round white icon behind header buttons ("bell", "+").
struct CircleIcon: View {
    let symbol: String
    var showsBadge = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 44, height: 44)
            .background(Theme.surface, in: Circle())
            .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    Circle()
                        .fill(Pastel.rose.base)
                        .frame(width: 9, height: 9)
                        .overlay { Circle().strokeBorder(Theme.surface, lineWidth: 1.5) }
                        .offset(x: -10, y: 10)
                }
            }
            .shadow(color: Theme.shadow, radius: 12, x: 0, y: 5)
    }
}

struct CircleIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var showsBadge = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleIcon(symbol: symbol, showsBadge: showsBadge)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(label))
    }
}

struct IconTile: View {
    let symbol: String
    let pastel: Pastel
    var size: CGFloat = Metrics.tileSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(pastel.strong)
            .frame(width: size, height: size)
            .background(pastel.soft, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

// MARK: - Headers

/// Large title at the top of each tab, with round buttons on the right.
struct ScreenHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(NookFont.greeting)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(title)
                    .font(NookFont.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                trailing
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Inputs

struct SearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField(prompt, text: $text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .strokeBorder(isFocused ? Theme.primary : Theme.border, lineWidth: 1)
        }
        .shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct ChipLabel: View {
    let title: LocalizedStringKey?
    var symbol: String? = nil
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
            }
            if let title {
                Text(title)
            }
        }
        .font(.system(.subheadline, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(isSelected ? Theme.primarySoft : Theme.surface, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isSelected ? Theme.primary.opacity(0.4) : Theme.border, lineWidth: 1)
        }
    }
}

struct Chip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, isSelected: isSelected)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Segmented control drawn as a white pill sliding on a soft track.
struct PillSegmentedControl<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> LocalizedStringKey
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(.system(.subheadline, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.surface)
                                    .shadow(color: Theme.shadow, radius: 6, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surfaceMuted, in: Capsule())
    }
}

// MARK: - Small pieces

/// "↓ -8.6%": green when spending went down, rose when it went up.
struct ChangeBadge: View {
    let change: Double

    var body: some View {
        let isDown = change < 0
        let pastel = isDown ? Pastel.mint : Pastel.rose
        HStack(spacing: 3) {
            Image(systemName: isDown ? "arrow.down" : "arrow.up")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: Self.percentText(change))
                .font(.system(.caption, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(pastel.strong)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(pastel.soft, in: Capsule())
    }

    static func percentText(_ change: Double) -> String {
        let text = change.formatted(.percent.precision(.fractionLength(1)))
        return change > 0 ? "+" + text : text
    }
}

/// Marks screens that only show demo content in this version.
struct PreviewBadge: View {
    var body: some View {
        Text("Preview")
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(Pastel.violet.strong)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Pastel.violet.soft, in: Capsule())
    }
}

struct ProgressCapsule: View {
    /// 0...1; values outside are clamped.
    let value: Double
    var pastel: Pastel = .mint

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceMuted)
                Capsule()
                    .fill(LinearGradient(colors: [pastel.base, pastel.strong], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.height, proxy.size.width * fraction))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.primary)
                .frame(width: 60, height: 60)
                .background(Theme.primarySoft, in: Circle())
            Text(title)
                .font(NookFont.rowTitle)
                .foregroundStyle(Theme.textPrimary)
            if let message {
                Text(message)
                    .font(NookFont.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Frosted strip under the status bar so scrolled content does not clash with the clock.
struct StatusBarScrim: View {
    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: proxy.safeAreaInsets.top + 10)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
