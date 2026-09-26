import Foundation
import SwiftData

/// Realistic demo caseload: Maria (the patient in the demo) plus a small clinic panel.
enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Patient>())) ?? 0
        if count == 0 { seed(context) }
    }

    @MainActor
    static func reset(_ context: ModelContext) {
        try? context.delete(model: RehabSession.self)
        try? context.delete(model: Patient.self)
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

        // James — week 6 plateau: the stiffness alert.
        addPatient(context, &rng, name: "James Okafor", age: 58, procedure: "Total knee replacement",
                   joint: .knee, side: .left, day: 43,
                   curve: [(1, 60), (7, 72), (14, 80), (21, 84), (28, 85), (35, 85), (42, 86)],
                   skip: [9, 30], pain: 4)
        // Tom — elbow fracture with a pain spike yesterday.
        addPatient(context, &rng, name: "Tom Becker", age: 45, procedure: "Elbow fracture repair",
                   joint: .elbow, side: .left, day: 30,
                   curve: [(1, 55), (10, 80), (20, 98), (28, 108), (29, 97)],
                   skip: [4, 15], pain: 3, lastPain: 8)
        // Lin — on track but missing days (RTM at risk).
        addPatient(context, &rng, name: "Lin Chen", age: 62, procedure: "Total knee replacement",
                   joint: .knee, side: .left, day: 25,
                   curve: [(1, 66), (7, 82), (14, 92), (19, 97)],
                   skip: [3, 8, 11, 20, 21, 22, 23, 24], pain: 3)
        // Priya — textbook recovery.
        addPatient(context, &rng, name: "Priya Shah", age: 71, procedure: "Total knee replacement",
                   joint: .knee, side: .right, day: 10,
                   curve: [(1, 70), (5, 80), (9, 88)],
                   skip: [], pain: 3)
        try? context.save()
    }

    @MainActor
    private static func addPatient(_ context: ModelContext, _ rng: inout SeededRandom, name: String, age: Int,
                                   procedure: String, joint: Joint, side: Side, day: Int,
                                   curve: [(Int, Double)], skip: Set<Int>, pain: Int, lastPain: Int? = nil) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let patient = Patient(name: name, age: age, procedure: procedure, joint: joint, side: side,
                              surgeryDate: cal.date(byAdding: .day, value: -day, to: today)!)
        context.insert(patient)
        let lastDay = curve.last!.0
        for d in 1...lastDay where !skip.contains(d) {
            let peak = interpolate(curve, Double(d)) + rng.next(in: -1.0...1.0)
            let session = RehabSession(
                date: cal.date(byAdding: .hour, value: 9, to: cal.date(byAdding: .day, value: -(day - d), to: today)!)!,
                peakFlexion: peak.rounded(), comfortableMax: (peak - 2).rounded(),
                extensionDeficit: max(2, 10 - Double(d) * 0.3).rounded(),
                reps: Int(rng.next(in: 8...14)), pain: d == lastDay ? (lastPain ?? pain) : pain,
                target: (peak + 4).rounded(), targetHeld: true)
            session.patient = patient
            context.insert(session)
        }
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
