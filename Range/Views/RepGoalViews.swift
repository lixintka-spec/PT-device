import SwiftUI

/// Choose how many reps to do: one number, a minus and a plus.
struct RepGoalPicker: View {
    @Binding var goal: Int
    var note: String? = "Each rep: bend, hold \(Int(SessionEngine.holdSeconds)) s, come back"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reps").font(.headline)
                if let note {
                    Text(note).font(.caption).foregroundStyle(RangeTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            StepButton(symbol: "minus", enabled: goal > 1) { goal -= 1 }
            Text("\(goal)")
                .font(RangeTheme.numeral(30, weight: .bold))
                .frame(minWidth: 46)
                .contentTransition(.numericText(value: Double(goal)))
                .animation(.snappy, value: goal)
            StepButton(symbol: "plus", enabled: goal < 30) { goal += 1 }
        }
        .sensoryFeedback(.selection, trigger: goal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reps")
        .accessibilityValue("\(goal)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: goal = min(30, goal + 1)
            case .decrement: goal = max(1, goal - 1)
            @unknown default: break
            }
        }
    }

    private struct StepButton: View {
        var symbol: String
        var enabled: Bool
        var action: () -> Void
        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(enabled ? 0.12 : 0.05), in: .circle)
            }
            .buttonStyle(.plain)
            .foregroundStyle(enabled ? .white : RangeTheme.tertiaryText)
            .disabled(!enabled)
        }
    }
}

/// Rep progress during a session: a dot per rep in the goal, filled as clean reps land.
struct RepProgress: View {
    var done: Int
    var goal: Int
    var flagged: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if goal <= 15 {
                HStack(spacing: 6) {
                    ForEach(0..<goal, id: \.self) { i in
                        Circle()
                            .fill(i < done ? RangeTheme.mint : Color.white.opacity(0.12))
                            .frame(width: 11, height: 11)
                            .scaleEffect(i == done - 1 ? 1.25 : 1)
                    }
                }
                .animation(.spring(duration: 0.35, bounce: 0.4), value: done)
            } else {
                ProgressView(value: Double(min(done, goal)), total: Double(goal))
                    .tint(RangeTheme.mint)
                    .frame(width: 180)
            }
            HStack(spacing: 8) {
                Text("\(min(done, goal)) of \(goal) reps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(done >= goal ? RangeTheme.mint : RangeTheme.secondaryText)
                    .contentTransition(.numericText(value: Double(done)))
                if flagged > 0 {
                    Text("\(flagged) didn't count")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RangeTheme.coral)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The three moves of every rep, with the current one lit: Bend → Hold 3s → Back.
struct RepLoopIndicator: View {
    var stage: SessionEngine.RepStage
    var holdMissed = false
    var large = false

    var body: some View {
        HStack(spacing: 6) {
            step(.out, "Bend", tint: RangeTheme.amber)
            arrow
            step(.hold, "Hold \(Int(SessionEngine.holdSeconds))s", tint: RangeTheme.amber, missed: holdMissed)
            arrow
            step(.back, "Back", tint: RangeTheme.sky)
        }
        .font(large ? .headline : .subheadline.weight(.semibold))
        .animation(.snappy, value: stage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rep: bend, hold, back")
        .accessibilityValue(stage == .out ? "Bend" : (stage == .hold ? "Hold" : "Back"))
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(RangeTheme.tertiaryText)
    }

    private func step(_ s: SessionEngine.RepStage, _ title: String, tint base: Color, missed: Bool = false) -> some View {
        let active = s == stage
        let done = s < stage
        let tint = done && missed ? RangeTheme.coral : base
        return HStack(spacing: 4) {
            if done { Image(systemName: missed ? "xmark" : "checkmark") }
            Text(title)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, large ? 14 : 10)
        .padding(.vertical, large ? 8 : 6)
        .foregroundStyle(active ? Color.black : (done ? tint : RangeTheme.secondaryText))
        .background(active ? tint : tint.opacity(done ? 0.14 : 0), in: .capsule)
        .overlay(Capsule().strokeBorder(Color.white.opacity(active || done ? 0 : 0.18)))
    }
}

/// The hold, impossible to miss: a ring that fills while the knee stays at the top.
struct HoldCountdown: View {
    var remaining: Double
    var progress: Double
    var paused: Bool
    var degrees: Double
    var diameter: CGFloat

    var body: some View {
        let tint = paused ? RangeTheme.coral : RangeTheme.amber
        let line = diameter * 0.075
        ZStack {
            Circle().fill(tint.opacity(0.10))
            Circle().stroke(tint.opacity(0.22), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: 12)
            VStack(spacing: 0) {
                if paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: diameter * 0.26, weight: .bold))
                        .padding(.vertical, diameter * 0.06)
                } else {
                    Text("\(Int(ceil(remaining)))")
                        .font(RangeTheme.numeral(diameter * 0.42, weight: .bold))
                        .contentTransition(.numericText(countsDown: true))
                }
                Text("\(Int(degrees.rounded()))°")
                    .font(RangeTheme.numeral(diameter * 0.11, weight: .semibold))
                    .foregroundStyle(RangeTheme.secondaryText)
            }
            .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 0.1), value: progress)
        .animation(.snappy, value: Int(ceil(remaining)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? "Hold paused" : "Hold, \(Int(ceil(remaining))) seconds left")
    }
}
