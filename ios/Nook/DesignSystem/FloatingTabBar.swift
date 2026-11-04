import SwiftUI

/// The floating tab bar, with the assistant button in the middle. Tap a tab, or press and slide
/// along the bar: the highlight follows the finger and the tab under it opens on release.
struct FloatingTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let onAssistant: () -> Void
    /// Finger position while sliding along the bar, in the bar's own coordinates.
    @State private var dragX: CGFloat?
    /// The tab under the finger while sliding; drives the haptic tick between tabs.
    @State private var hovered: AppTab?

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 350
            let inset = compact ? 6 : Metrics.screenPadding
            let layout = TabBarLayout(width: max(proxy.size.width - inset * 2, 0), assistantWidth: compact ? 44 : 52)
            let highlighted = hovered ?? selection
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.primarySoft)
                    .frame(width: 40, height: 40)
                    .scaleEffect(dragX == nil ? 1 : 1.18)
                    .position(x: dragX ?? layout.center(of: selection), y: 32)
                    .animation(.spring(response: 0.32, dampingFraction: 0.8), value: selection)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(TabBarLayout.leftTabs) { tab in
                        tabButton(tab, highlighted: tab == highlighted)
                            .frame(width: layout.leftWidth)
                    }
                    assistantButton(compact: compact)
                        .frame(width: layout.assistantWidth)
                    ForEach(TabBarLayout.rightTabs) { tab in
                        tabButton(tab, highlighted: tab == highlighted)
                            .frame(width: layout.rightWidth)
                    }
                }
            }
            .frame(width: layout.width, height: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.border, lineWidth: 1) }
            .shadow(color: Theme.shadow, radius: 20, x: 0, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            // Taps still reach the buttons; a drag of a few points takes over and slides instead.
            .highPriorityGesture(slide(layout))
            .padding(.horizontal, inset)
        }
        .frame(height: 64)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.selection, trigger: hovered) { old, new in old != nil && new != nil }
    }

    private func slide(_ layout: TabBarLayout) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                let x = min(max(value.location.x, 24), max(layout.width - 24, 24))
                if dragX == nil {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { dragX = x }
                } else {
                    dragX = x
                }
                let tab = layout.tab(at: x)
                if tab != hovered {
                    withAnimation(.easeOut(duration: 0.15)) { hovered = tab }
                }
            }
            .onEnded { value in
                let tab = layout.tab(at: min(max(value.location.x, 0), layout.width))
                if tab != selection {
                    onSelect(tab)
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    dragX = nil
                    hovered = nil
                }
            }
    }

    private func tabButton(_ tab: AppTab, highlighted: Bool) -> some View {
        Button { onSelect(tab) } label: {
            Image(systemName: tab.symbol)
                .symbolVariant(highlighted ? .fill : .none)
                .font(.system(size: 19, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? Theme.accent : Theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(tab == selection ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }

    private func assistantButton(compact: Bool) -> some View {
        Button(action: onAssistant) {
            VStack(spacing: 2) {
                Image(systemName: "sparkles").font(.system(size: 21, weight: .semibold))
                Text(verbatim: "Nook").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.onNavy)
            .frame(width: compact ? 44 : 52, height: 52)
            .background(Theme.navy, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Ask Nook"))
        .accessibilityIdentifier("tab.assistant")
    }
}

/// Where each tab sits: three tabs left of the assistant button and two to its right, with the
/// two sides equally wide so the assistant stays centered.
private struct TabBarLayout {
    static let leftTabs: [AppTab] = [.home, .notes, .vault]
    static let rightTabs: [AppTab] = [.schedule, .finance]

    let width: CGFloat
    let assistantWidth: CGFloat

    var sideWidth: CGFloat { max((width - assistantWidth) / 2, 0) }
    var leftWidth: CGFloat { sideWidth / CGFloat(Self.leftTabs.count) }
    var rightWidth: CGFloat { sideWidth / CGFloat(Self.rightTabs.count) }

    func center(of tab: AppTab) -> CGFloat {
        if let index = Self.leftTabs.firstIndex(of: tab) {
            return leftWidth * (CGFloat(index) + 0.5)
        }
        let index = Self.rightTabs.firstIndex(of: tab) ?? 0
        return sideWidth + assistantWidth + rightWidth * (CGFloat(index) + 0.5)
    }

    /// The tab under `x`; over the assistant button, whichever neighbour is nearer.
    func tab(at x: CGFloat) -> AppTab {
        if x < sideWidth {
            let index = Int(x / max(leftWidth, 1))
            return Self.leftTabs[min(max(index, 0), Self.leftTabs.count - 1)]
        }
        if x >= sideWidth + assistantWidth {
            let index = Int((x - sideWidth - assistantWidth) / max(rightWidth, 1))
            return Self.rightTabs[min(max(index, 0), Self.rightTabs.count - 1)]
        }
        return x < sideWidth + assistantWidth / 2 ? Self.leftTabs[Self.leftTabs.count - 1] : Self.rightTabs[0]
    }
}
