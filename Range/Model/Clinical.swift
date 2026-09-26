import Foundation
import SwiftUI

/// Clinical rules of thumb. Values are illustrative for the demo and would be
/// configured per surgeon protocol in production.
enum Clinical {
    /// Change smaller than this is within goniometric measurement error (minimal detectable change).
    static let measurementNoise: Double = 5
    /// Remote Therapeutic Monitoring device-supply billing needs 16 days of data in a 30-day period.
    static let rtmRequiredDays = 16

    /// Typical flexion range after total knee replacement by day after surgery (lower, upper).
    static func expectedKneeBand(day: Double) -> (low: Double, high: Double) {
        let points: [(Double, Double, Double)] = [
            (0, 50, 75), (7, 70, 90), (14, 80, 100), (21, 88, 105), (42, 100, 118), (84, 110, 125), (180, 115, 130),
        ]
        guard day > points.first!.0 else { return (points.first!.1, points.first!.2) }
        for i in 1..<points.count where day <= points[i].0 {
            let a = points[i - 1], b = points[i]
            let t = (day - a.0) / (b.0 - a.0)
            return (a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        return (points.last!.1, points.last!.2)
    }

    static func expectedBand(joint: Joint, day: Double) -> (low: Double, high: Double) {
        switch joint {
        case .knee: return expectedKneeBand(day: day)
        case .elbow:
            let k = expectedKneeBand(day: day)
            return (k.low + 5, k.high + 10)
        }
    }
}

enum Risk: Int, Comparable {
    case onTrack = 0, missedDays = 1, painSpike = 2, stiffness = 3

    static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .onTrack: "On track"
        case .missedDays: "Missed sessions"
        case .painSpike: "Pain spike"
        case .stiffness: "Stiffness risk"
        }
    }
    var tint: Color {
        switch self {
        case .onTrack: RangeTheme.mint
        case .missedDays: RangeTheme.sky
        case .painSpike: RangeTheme.amber
        case .stiffness: RangeTheme.coral
        }
    }
    var symbol: String {
        switch self {
        case .onTrack: "checkmark.circle.fill"
        case .missedDays: "calendar.badge.exclamationmark"
        case .painSpike: "bolt.heart.fill"
        case .stiffness: "exclamationmark.triangle.fill"
        }
    }
}

extension Patient {
    var sortedSessions: [RehabSession] { sessions.sorted { $0.date < $1.date } }

    func day(of date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: surgeryDate),
                                        to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
    var dayToday: Int { day(of: .now) }
    var weekToday: Int { dayToday / 7 + 1 }

    var lastSession: RehabSession? { sortedSessions.last }
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

    /// Days with data in the last 30 days (Remote Therapeutic Monitoring).
    var rtmDays: Int {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -30, to: .now)!
        return Set(sessions.filter { $0.date >= cutoff }.map { cal.startOfDay(for: $0.date) }).count
    }

    var daysSinceLastSession: Int {
        guard let last = lastSession else { return 99 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last.date),
                                               to: Calendar.current.startOfDay(for: .now)).day ?? 0
    }

    var extensionDeficit: Double { lastSession?.extensionDeficit ?? 0 }

    var risk: Risk {
        let s = sortedSessions
        if let last = s.last {
            let priorBest = s.dropLast().map(\.peakFlexion).max() ?? last.peakFlexion
            if last.pain >= 7 || priorBest - last.peakFlexion >= 8 { return .painSpike }
        }
        if dayToday >= 35 {
            let recent = s.suffix(8).map(\.peakFlexion)
            let gain = (recent.max() ?? 0) - (recent.min() ?? 0)
            if bestFlexion < 90 && gain < 6 { return .stiffness }
        }
        if daysSinceLastSession >= 4 { return .missedDays }
        return .onTrack
    }

    var riskDetail: String {
        switch risk {
        case .stiffness:
            return "Plateaued at \(Int(bestFlexion))° in week \(weekToday). Under 90° around week 6 is when surgeons consider manipulation. Flag for surgeon review."
        case .painSpike:
            let last = lastSession
            return "Last session: pain \(last?.pain ?? 0)/10 and peak \(Int(last?.peakFlexion ?? 0))°. Check in today — possible flare or swelling."
        case .missedDays:
            return "No sessions for \(daysSinceLastSession) days. \(rtmDays)/\(Clinical.rtmRequiredDays) RTM days this period."
        case .onTrack:
            return "Within the typical recovery range for week \(weekToday)."
        }
    }

    var nextMilestone: Milestone? { joint.milestones.first { $0.degrees > bestFlexion } }
    var reachedMilestones: [Milestone] { joint.milestones.filter { $0.degrees <= bestFlexion } }
}
