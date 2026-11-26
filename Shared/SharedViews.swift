import SwiftUI

extension Derived.Tone {
    var color: Color {
        switch self {
        case .good: return Color(red: 0.24, green: 0.72, blue: 0.45)
        case .caution: return Color(red: 0.93, green: 0.64, blue: 0.20)
        case .low: return Color(red: 0.92, green: 0.38, blue: 0.32)
        case .none: return .secondary
        }
    }
}

extension PlannedRun.Kind {
    var color: Color {
        switch self {
        case .easy: return Color(red: 0.36, green: 0.62, blue: 0.85)
        case .workout: return Color(red: 0.93, green: 0.55, blue: 0.22)
        case .long: return Color(red: 0.25, green: 0.66, blue: 0.52)
        case .race: return Color(red: 0.86, green: 0.30, blue: 0.36)
        }
    }

    var symbol: String {
        switch self {
        case .easy: return "figure.run"
        case .workout: return "bolt.fill"
        case .long: return "road.lanes"
        case .race: return "flag.checkered"
        }
    }
}

struct RingView: View {
    let ring: Derived.Ring
    var size: CGFloat = 64
    var line: CGFloat = 7
    var showLabels = true

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: line)
                if let f = ring.fraction {
                    Circle()
                        .trim(from: 0, to: max(0.001, min(1, f)))
                        .stroke(ring.tone.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(ring.value)
                    .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, line + 2)
            }
            .frame(width: size, height: size)
            if showLabels {
                Text(ring.label).font(.caption2).foregroundStyle(.secondary)
                if !ring.sub.isEmpty {
                    Text(ring.sub).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ring.label) \(ring.value) \(ring.sub)")
    }
}

/// Progress bar from best half (left) to the goal (right) with the current prediction.
struct GoalBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.44, blue: 0.70), Color(red: 0.18, green: 0.65, blue: 0.60)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, g.size.width * progress))
            }
        }
        .frame(height: 8)
    }
}
