import SwiftUI

/// Choose how many reps to do: one number, a minus and a plus.
struct RepGoalPicker: View {
    @Binding var goal: Int
    var note: String? = "Dr. Kim suggests 10"

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
