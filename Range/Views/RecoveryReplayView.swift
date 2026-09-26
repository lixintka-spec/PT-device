import SwiftUI

/// Not a chart: the joint literally regains its range, day by day.
struct RecoveryReplayView: View {
    var patient: Patient
    var compact = false
    var autoplay = true

    @State private var index = -1
    @State private var flexion: Double = 0
    @State private var playID = UUID()

    struct Keyframe: Hashable {
        let day: Int
        let flexion: Double
        let isToday: Bool
    }

    private var keyframes: [Keyframe] {
        let sessions = patient.sortedSessions
        guard !sessions.isEmpty else { return [] }
        let todayStart = Calendar.current.startOfDay(for: .now)
        let latest = sessions.last!
        let latestDay = patient.day(of: latest.date)
        var picks: [Keyframe] = []
        for wanted in [1, 7, latestDay - 1] {
            let before = sessions.filter { $0.date < latest.date }
            if let s = before.min(by: { abs(patient.day(of: $0.date) - wanted) < abs(patient.day(of: $1.date) - wanted) }) {
                let k = Keyframe(day: patient.day(of: s.date), flexion: s.peakFlexion, isToday: false)
                if !picks.contains(where: { $0.day == k.day }) { picks.append(k) }
            }
        }
        picks.append(Keyframe(day: latestDay, flexion: latest.peakFlexion, isToday: latest.date >= todayStart))
        return picks
    }

    private let palette: [Color] = [RangeTheme.lilac.opacity(0.55), RangeTheme.sky.opacity(0.6), RangeTheme.mint.opacity(0.6), RangeTheme.amber]

    var body: some View {
        let frames = keyframes
        VStack(alignment: .leading, spacing: compact ? 6 : 12) {
            HStack {
                Label("Recovery replay", systemImage: "play.circle.fill")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Button {
                    playID = UUID()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Replay")
            }
            ZStack(alignment: .topLeading) {
                LimbFigure(flexion: flexion, joint: patient.joint,
                           arcs: frames.prefix(max(0, index + 1)).enumerated().map { ($0.element.flexion, palette[min($0.offset, palette.count - 1)]) },
                           showDevice: true)
                if index >= 0, index < frames.count {
                    let k = frames[index]
                    VStack(alignment: .leading, spacing: 0) {
                        Text(k.isToday ? "Today" : "Day \(k.day)")
                            .font(compact ? .headline : .title2.weight(.semibold))
                            .foregroundStyle(k.isToday ? RangeTheme.amber : .white)
                            .contentTransition(.interpolate)
                        Text("\(Int(flexion.rounded()))°")
                            .font(RangeTheme.numeral(compact ? 40 : 56, weight: .bold))
                            .contentTransition(.numericText(value: flexion))
                    }
                }
            }
            .frame(minHeight: compact ? 200 : 240)
            HStack(spacing: 6) {
                ForEach(Array(frames.enumerated()), id: \.offset) { i, k in
                    VStack(spacing: 2) {
                        Text(k.isToday ? "Today" : "Day \(k.day)").font(.caption2)
                        Text("\(Int(k.flexion))°").font(RangeTheme.numeral(13, weight: .bold))
                    }
                    .foregroundStyle(i <= index ? palette[min(i, palette.count - 1)] : RangeTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: playID) {
            guard autoplay || playID != UUID() else { return }
            index = -1
            flexion = 0
            try? await Task.sleep(for: .milliseconds(400))
            for i in frames.indices {
                withAnimation(.spring(duration: 1.1, bounce: 0.18)) {
                    index = i
                    flexion = frames[i].flexion
                }
                try? await Task.sleep(for: .milliseconds(i == frames.count - 1 ? 0 : 1500))
            }
        }
    }
}
