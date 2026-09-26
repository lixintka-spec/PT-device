import Foundation
import FoundationModels

/// Drafts a therapist progress note. Uses Apple's on-device model when available so
/// patient data never leaves the phone; otherwise a deterministic clinical template.
enum NoteGenerator {
    struct Result {
        let text: String
        let source: String
    }

    @MainActor
    static func draft(for patient: Patient) async -> Result {
        let facts = factSheet(for: patient)
        if case .available = SystemLanguageModel.default.availability {
            do {
                let session = LanguageModelSession(instructions: """
                You are a licensed physical therapist writing a concise SOAP progress note for a remote \
                therapeutic monitoring record. Use only the facts provided. No diagnosis beyond them. \
                Four short sections: S, O, A, P. Under 140 words.
                """)
                let response = try await session.respond(to: facts)
                return Result(text: response.content, source: "On-device model")
            } catch {
                // fall through to template
            }
        }
        return Result(text: template(for: patient), source: "On-device template")
    }

    @MainActor
    static func factSheet(for p: Patient) -> String {
        let recent = p.sortedSessions.suffix(5).map { "day \(p.day(of: $0.date)): peak \(Int($0.peakFlexion))°, pain \($0.pain)/10, reps \($0.reps)" }
        return """
        Patient: \(p.age)-year-old, \(p.procedure), \(p.side.rawValue) \(p.joint.rawValue), day \(p.dayToday) (week \(p.weekToday)).
        Best flexion \(Int(p.bestFlexion))°, comfortable max \(Int(p.comfortableMax))°, extension deficit \(Int(p.extensionDeficit))°.
        Recent sessions: \(recent.joined(separator: "; ")).
        Risk flag: \(p.risk.title) — \(p.riskDetail)
        RTM data days this period: \(p.rtmDays)/\(Clinical.rtmRequiredDays).
        """
    }

    @MainActor
    static func template(for p: Patient) -> String {
        let sessions = p.sortedSessions
        let weekAgo = sessions.first(where: { p.day(of: $0.date) >= p.dayToday - 7 })?.peakFlexion ?? p.bestFlexion
        let gain = p.bestFlexion - weekAgo
        let band = Clinical.expectedBand(joint: p.joint, day: Double(p.dayToday))
        let pain = sessions.last?.pain ?? 0
        let plan: String
        switch p.risk {
        case .stiffness: plan = "Escalate: notify surgeon re: flexion plateau <90° at week \(p.weekToday); increase session frequency to 3x/day; add prolonged low-load stretch."
        case .painSpike: plan = "Hold progression 48h; check effusion and incision; call patient today."
        case .missedDays: plan = "Adherence outreach today; \(Clinical.rtmRequiredDays - min(Clinical.rtmRequiredDays, p.rtmDays)) more data days needed this period."
        case .onTrack: plan = "Progress target to \(Int(p.adaptiveTarget + 3))°; continue extension work; reassess in 1 week."
        }
        return """
        S: Pt reports pain \(pain)/10 with home program. \(p.streak)-day adherence streak.
        O: Remote goniometry (hinge sensor), \(p.side.rawValue) \(p.joint.rawValue): flexion \(Int(p.bestFlexion))° (\(gain >= 0 ? "+" : "")\(Int(gain))° over 7 days), extension deficit \(Int(p.extensionDeficit))°. \(sessions.suffix(7).map(\.reps).reduce(0, +)) reps logged this week. RTM days \(p.rtmDays)/\(Clinical.rtmRequiredDays).
        A: \(p.risk == .onTrack ? "Progressing within" : "Outside") typical range for week \(p.weekToday) (\(Int(band.low))–\(Int(band.high))°). \(gain >= Clinical.measurementNoise ? "Gain exceeds measurement error." : "Change within measurement error.")
        P: \(plan)
        """
    }
}
