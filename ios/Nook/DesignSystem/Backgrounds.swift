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

// MARK: - Mt. Fuji thumbnail

/// A drawn photo of Mt. Fuji with cherry blossoms, used for the sample trip note.
struct FujiThumbnail: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xBFD9F5), Color(hex: 0xEAF3FC)], startPoint: .top, endPoint: .bottom)
            GeometryReader { proxy in
                Circle()
                    .fill(Color(hex: 0xFFF3DF))
                    .frame(width: proxy.size.width * 0.2, height: proxy.size.width * 0.2)
                    .position(x: proxy.size.width * 0.78, y: proxy.size.height * 0.22)
            }
            MountainShape()
                .fill(LinearGradient(colors: [Color(hex: 0x86A2CC), Color(hex: 0x5873A3)], startPoint: .top, endPoint: .bottom))
            MountainShape()
                .fill(Color.white)
                .mask { SnowRegion() }
            WaveShape(baseline: 0.9, amplitude: 3, wavelength: 0.7, phase: 0.2, fillsBelow: true)
                .fill(Color(hex: 0x6E8FB8).opacity(0.55))
            BlossomBranch()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(Text("Photo of Mt. Fuji"))
    }
}

private struct MountainShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - width * 0.05, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.42, y: rect.minY + height * 0.36),
            control: CGPoint(x: rect.minX + width * 0.28, y: rect.minY + height * 0.8)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.58, y: rect.minY + height * 0.36))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + width * 0.05, y: rect.maxY),
            control: CGPoint(x: rect.minX + width * 0.72, y: rect.minY + height * 0.8)
        )
        path.closeSubpath()
        return path
    }
}

/// Everything above a zigzag snow line.
private struct SnowRegion: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.70, 0.55), (0.63, 0.50), (0.57, 0.56), (0.50, 0.49), (0.44, 0.56), (0.37, 0.50), (0.30, 0.55),
        ]
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.55))
        for (x, y) in points {
            path.addLine(to: CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.closeSubpath()
        return path
    }
}

private struct BlossomBranch: View {
    private struct Petal {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let isLight: Bool
    }

    private static let petals: [Petal] = [
        Petal(x: 0.08, y: 0.10, size: 0.16, isLight: false),
        Petal(x: 0.20, y: 0.05, size: 0.12, isLight: true),
        Petal(x: 0.30, y: 0.13, size: 0.10, isLight: false),
        Petal(x: 0.13, y: 0.22, size: 0.10, isLight: true),
        Petal(x: 0.03, y: 0.30, size: 0.09, isLight: false),
        Petal(x: 0.92, y: 0.86, size: 0.15, isLight: true),
        Petal(x: 0.82, y: 0.93, size: 0.11, isLight: false),
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: height * 0.18))
                path.addQuadCurve(
                    to: CGPoint(x: width * 0.34, y: height * 0.06),
                    control: CGPoint(x: width * 0.16, y: height * 0.2)
                )
            }
            .stroke(Color(hex: 0x8C6E63), lineWidth: max(1, width * 0.018))
            ForEach(Self.petals.indices, id: \.self) { index in
                let petal = Self.petals[index]
                Circle()
                    .fill(petal.isLight ? Color(hex: 0xFBD9E3) : Color(hex: 0xF3AFC3))
                    .frame(width: width * petal.size, height: width * petal.size)
                    .position(x: width * petal.x, y: height * petal.y)
            }
        }
    }
}
