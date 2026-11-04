import SwiftUI

/// The floating white tab bar. Home's selected state is a navy circle; the other tabs get a
/// light-blue pill. One indicator slides between items.
struct FloatingTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .symbolVariant(tab == selection ? .fill : .none)
                        .font(.system(size: 19, weight: tab == selection ? .semibold : .regular))
                        .foregroundStyle(iconColor(for: tab))
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(tab.title))
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityAddTraits(tab == selection ? .isSelected : [])
            }
        }
        .background { indicator }
        .animation(.easeOut(duration: 0.2), value: selection)
        .padding(.horizontal, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: Theme.shadow, radius: 20, x: 0, y: 10)
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var indicator: some View {
        GeometryReader { proxy in
            let itemWidth = proxy.size.width / CGFloat(AppTab.allCases.count)
            let isHome = selection == .home
            let size = isHome ? CGSize(width: 46, height: 46) : CGSize(width: 58, height: 40)
            RoundedRectangle(cornerRadius: size.height / 2, style: .continuous)
                .fill(isHome ? Theme.navy : Theme.primarySoft)
                .frame(width: size.width, height: size.height)
                .position(x: itemWidth * (CGFloat(selection.index) + 0.5), y: proxy.size.height / 2)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: selection)
        .allowsHitTesting(false)
    }

    private func iconColor(for tab: AppTab) -> Color {
        guard tab == selection else { return Theme.textSecondary }
        return tab == .home ? Theme.onNavy : Theme.accent
    }
}
