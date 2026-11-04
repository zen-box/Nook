import SwiftUI

/// A centered assistant action; all five destinations stay one tap away.
struct FloatingTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void
    let onAssistant: () -> Void
    @Namespace private var selectionAnimation

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 350
            HStack(spacing: 0) {
                HStack(spacing: 0) { tab(.home); tab(.notes); tab(.vault) }.frame(maxWidth: .infinity)
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
                HStack(spacing: 0) { tab(.schedule); tab(.finance) }.frame(maxWidth: .infinity)
            }
            .frame(height: 64)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.border, lineWidth: 1) }
            .shadow(color: Theme.shadow, radius: 20, x: 0, y: 10)
            .padding(.horizontal, compact ? 6 : Metrics.screenPadding)
        }
        .frame(height: 64)
        .padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tab(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button { onSelect(tab) } label: {
            Image(systemName: tab.symbol)
                .symbolVariant(selected ? .fill : .none)
                .font(.system(size: 19, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 64)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 15).fill(Theme.primarySoft)
                            .frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "tabSelection", in: selectionAnimation)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }
}
