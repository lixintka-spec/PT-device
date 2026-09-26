import Foundation
import SwiftData

/// Demo data: Maria, day 14 after a knee replacement, with two weeks of sessions.
enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Patient>())) ?? 0
        if count == 0 { seed(context) }
    }

    @MainActor
    static func reset(_ context: ModelContext) {
        // Delete object by object: batch deletes trip over the patient ↔ session inverse.
        for patient in (try? context.fetch(FetchDescriptor<Patient>())) ?? [] { context.delete(patient) }
        for session in (try? context.fetch(FetchDescriptor<RehabSession>())) ?? [] { context.delete(session) }
        try? context.save()
        seed(context)
    }

    @MainActor
    private static func seed(_ context: ModelContext) {
        var rng = SeededRandom(seed: 42)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }

        // Maria — day 14 after a right total knee replacement. The demo patient.
        let maria = Patient(name: "Maria Alvarez", age: 67, procedure: "Total knee replacement",
                            joint: .knee, side: .right, surgeryDate: daysAgo(14), isPrimary: true)
        context.insert(maria)
        let mariaCurve: [(Int, Double)] = [(1, 66), (3, 70), (7, 78), (10, 81), (13, 84)]
        let pinned: [Int: Double] = [11: 83, 12: 84, 13: 84]
        for day in 1...13 where day != 5 {
            let peak = pinned[day] ?? (interpolate(mariaCurve, Double(day)) + rng.next(in: -1.0...1.0)).rounded()
            let session = RehabSession(
                date: cal.date(byAdding: .hour, value: 10, to: daysAgo(14 - day))!,
                peakFlexion: peak,
                comfortableMax: (peak - 2).rounded(),
                extensionDeficit: max(3, 12 - Double(day) * 0.6).rounded(),
                reps: Int(rng.next(in: 10...15)),
                compensatedReps: Int(rng.next(in: 0...2)),
                pain: max(2, 6 - day / 4),
                target: (peak + 4).rounded(),
                targetHeld: day % 3 != 0)
            session.patient = maria
            context.insert(session)
        }

        try? context.save()
    }

    static func interpolate(_ points: [(Int, Double)], _ x: Double) -> Double {
        guard let first = points.first else { return 0 }
        if x <= Double(first.0) { return first.1 }
        for i in 1..<points.count where x <= Double(points[i].0) {
            let a = points[i - 1], b = points[i]
            let t = (x - Double(a.0)) / Double(b.0 - a.0)
            return a.1 + (b.1 - a.1) * t
        }
        return points.last!.1
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func nextUnit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }
}
