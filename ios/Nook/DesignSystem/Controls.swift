import SwiftUI

/// The filled blue button used for the main action of a card.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    var isWorking = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .tint(.white)
                } else if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isEnabled ? Theme.accent : Theme.textTertiary, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

/// A light-blue secondary button.
struct SoftButton: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

/// A password box with a button to show what was typed.
struct PasswordField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .foregroundStyle(Theme.textTertiary)
            Group {
                if isRevealed {
                    TextField(prompt, text: $text)
                } else {
                    SecureField(prompt, text: $text)
                }
            }
            .font(.subheadline)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? Text("Hide password") : Text("Show password"))
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous))
    }
}
