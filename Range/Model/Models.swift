import Foundation
import SwiftData

enum Joint: String, Codable, CaseIterable, Identifiable {
    case knee, elbow
    var id: String { rawValue }
    var title: String { self == .knee ? "Knee" : "Elbow" }
    var symbol: String { self == .knee ? "figure.walk" : "figure.arms.open" }
    var fullExtensionLabel: String { self == .knee ? "straight leg" : "straight arm" }

    var milestones: [Milestone] {
        switch self {
        case .knee:
            return [
                Milestone(degrees: 65, title: "Walk normally", symbol: "figure.walk"),
                Milestone(degrees: 85, title: "Climb stairs", symbol: "figure.stairs"),
                Milestone(degrees: 95, title: "Stand up from a chair", symbol: "chair.fill"),
                Milestone(degrees: 100, title: "Walk down stairs", symbol: "figure.stair.stepper"),
                Milestone(degrees: 110, title: "Ride a bike", symbol: "bicycle"),
                Milestone(degrees: 120, title: "Kneel in the garden", symbol: "leaf.fill"),
            ]
        case .elbow:
            return [
                Milestone(degrees: 60, title: "Carry a bag", symbol: "bag.fill"),
                Milestone(degrees: 90, title: "Type at a desk", symbol: "keyboard"),
                Milestone(degrees: 115, title: "Eat with a fork", symbol: "fork.knife"),
                Milestone(degrees: 130, title: "Wash your face", symbol: "drop.fill"),
            ]
        }
    }
}

struct Milestone: Identifiable, Hashable {
    var degrees: Double
    var title: String
    var symbol: String
    var id: String { title }
}

enum Side: String, Codable, CaseIterable {
    case left, right
    var short: String { self == .left ? "L" : "R" }
    var title: String { rawValue.capitalized }
}

@Model
final class Patient {
    var id: UUID
    var name: String
    var age: Int
    var procedure: String
    var jointRaw: String
    var sideRaw: String
    var surgeryDate: Date
    var isPrimary: Bool
    @Relationship(deleteRule: .cascade, inverse: \RehabSession.patient)
    var sessions: [RehabSession] = []

    init(name: String, age: Int, procedure: String, joint: Joint, side: Side, surgeryDate: Date, isPrimary: Bool = false) {
        self.id = UUID()
        self.name = name
        self.age = age
        self.procedure = procedure
        self.jointRaw = joint.rawValue
        self.sideRaw = side.rawValue
        self.surgeryDate = surgeryDate
        self.isPrimary = isPrimary
    }

    var joint: Joint { Joint(rawValue: jointRaw) ?? .knee }
    var side: Side { Side(rawValue: sideRaw) ?? .right }
    var firstName: String { name.components(separatedBy: " ").first ?? name }
    var initials: String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }
}

@Model
final class RehabSession {
    var id: UUID
    var date: Date
    var peakFlexion: Double
    var comfortableMax: Double
    var extensionDeficit: Double
    var reps: Int
    var compensatedReps: Int
    var fastReps: Int
    var pain: Int
    var target: Double
    var targetHeld: Bool
    /// Where the patient chose to start stretching (0 = straight).
    var startFlexion: Double = 0
    var patient: Patient?

    init(date: Date, peakFlexion: Double, comfortableMax: Double, extensionDeficit: Double,
         reps: Int, compensatedReps: Int = 0, fastReps: Int = 0, pain: Int, target: Double, targetHeld: Bool) {
        self.id = UUID()
        self.date = date
        self.peakFlexion = peakFlexion
        self.comfortableMax = comfortableMax
        self.extensionDeficit = extensionDeficit
        self.reps = reps
        self.compensatedReps = compensatedReps
        self.fastReps = fastReps
        self.pain = pain
        self.target = target
        self.targetHeld = targetHeld
    }
}
