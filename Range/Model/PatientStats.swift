import Foundation

extension Patient {
    var sortedSessions: [RehabSession] { sessions.sorted { $0.date < $1.date } }

    func day(of date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: surgeryDate),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
    var dayToday: Int { day(of: .now) }

    var bestFlexion: Double { sessions.map(\.peakFlexion).max() ?? 0 }
    /// Best before today — what "last best" means at the start of a session.
    var bestBeforeToday: Double {
        let start = Calendar.current.startOfDay(for: .now)
        return sessions.filter { $0.date < start }.map(\.peakFlexion).max() ?? bestFlexion
    }

    /// Comfortable max = median peak of the last three sessions, not the single best rep.
    var comfortableMax: Double {
        let start = Calendar.current.startOfDay(for: .now)
        let recent = sortedSessions.filter { $0.date < start }.suffix(3).map(\.peakFlexion).sorted()
        guard !recent.isEmpty else { return 0 }
        return recent[recent.count / 2]
    }

    /// Adaptive target: a small, safe step beyond the comfortable max. Smaller step if it hurt last time.
    var adaptiveTarget: Double {
        let lastPain = sortedSessions.last(where: { $0.date < Calendar.current.startOfDay(for: .now) })?.pain ?? 0
        let step: Double = lastPain >= 5 ? 2 : 5
        return (comfortableMax + step).rounded()
    }

    var streak: Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.date) })
        var count = 0
        var cursor = cal.startOfDay(for: .now)
        if !days.contains(cursor) { cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }
        while days.contains(cursor) {
            count += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    /// Degrees gained since the very first session.
    var gainSinceFirstSession: Double { max(0, bestFlexion - (sortedSessions.first?.peakFlexion ?? bestFlexion)) }

    var nextMilestone: Milestone? { joint.milestones.first { $0.degrees > bestFlexion } }
    var reachedMilestones: [Milestone] { joint.milestones.filter { $0.degrees <= bestFlexion } }
}
