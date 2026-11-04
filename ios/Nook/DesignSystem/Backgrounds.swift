import SwiftUI

/// A sine wave. Fills the area above the wave, or below it with `fillsBelow`.
struct WaveShape: Shape {
    /// Height of the wave's middle line as a fraction of the rect.
    let baseline: CGFloat
    let amplitude: CGFloat
    /// Wave length as a fraction of the width.
    let wavelength: CGFloat
    /// 0...1, shifts the wave sideways.
    let phase: CGFloat
    var fillsBelow = false

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.minY + rect.height * baseline
        let edgeY = fillsBelow ? rect.maxY : rect.minY
        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        let steps = 60
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = (progress / wavelength + phase) * 2 * .pi
            path.addLine(to: CGPoint(x: rect.minX + rect.width * progress, y: midY + sin(angle) * amplitude))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: edgeY))
        path.closeSubpath()
        return path
    }
}

/// Just the wave line, for soft blurred ribbons.
struct WaveLine: Shape {
    let baseline: CGFloat
    let amplitude: CGFloat
    let wavelength: CGFloat
    let phase: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.minY + rect.height * baseline
        let steps = 60
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = (progress / wavelength + phase) * 2 * .pi
            let point = CGPoint(x: rect.minX + rect.width * progress, y: midY + sin(angle) * amplitude)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// The soft misty-blue waves behind the home header.
struct MistyBackground: View {
    var height: CGFloat = 380

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Theme.mistTop, Theme.mistTop.opacity(0.55), Theme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            WaveLine(baseline: 0.34, amplitude: 24, wavelength: 1.25, phase: 0.15)
                .stroke(Theme.mistGlow, lineWidth: 46)
                .blur(radius: 22)
            WaveLine(baseline: 0.52, amplitude: 20, wavelength: 0.95, phase: 0.6)
                .stroke(Theme.mistWave.opacity(0.75), lineWidth: 34)
                .blur(radius: 20)
            WaveLine(baseline: 0.62, amplitude: 14, wavelength: 1.6, phase: 0.35)
                .stroke(Theme.mistGlow.opacity(0.7), lineWidth: 18)
                .blur(radius: 14)
            RadialGradient(
                colors: [Theme.mistGlow.opacity(0.9), .clear],
                center: UnitPoint(x: 0.92, y: 0),
                startRadius: 0,
                endRadius: 260
            )
        }
        .frame(height: height)
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}
