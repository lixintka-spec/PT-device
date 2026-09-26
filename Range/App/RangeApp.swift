import SwiftUI
import SwiftData

@main
struct RangeApp: App {
    @State private var hinge = HingeEngine()
    @State private var leveler = Leveler()
    @State private var session = SessionEngine()
    @State private var store = ProStore()
    @State private var app = AppState()
    private let feedback = FeedbackCoordinator()
    private let container: ModelContainer

    init() {
        let schema = Schema([Patient.self, RehabSession.self])
        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        if ProcessInfo.processInfo.arguments.contains("-resetDemo") {
            SeedData.reset(container.mainContext)
        } else {
            SeedData.seedIfNeeded(container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hinge)
                .environment(leveler)
                .environment(session)
                .environment(store)
                .environment(app)
                .preferredColorScheme(.dark)
                .task {
                    session.attach(hinge: hinge, leveler: leveler, feedback: feedback)
                    app.attach(hinge: hinge, leveler: leveler, session: session, feedback: feedback)
                    store.configure()
                    for _ in 0..<20 where app.primaryPatient == nil { try? await Task.sleep(for: .milliseconds(100)) }
                    if ProcessInfo.processInfo.arguments.contains("-startSession"), let p = app.primaryPatient {
                        session.configure(for: p)
                        app.tab = .exercise
                        session.begin()
                    }
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
                        app.tab = ["home": .home, "today": .home, "exercise": .exercise, "session": .exercise,
                                   "progress": .progress][args[i + 1]] ?? .home
                    }
                    if let i = args.firstIndex(of: "-repGoal"), i + 1 < args.count, let n = Int(args[i + 1]) { session.repGoal = min(30, max(1, n)) }
                    if ProcessInfo.processInfo.arguments.contains("-autopilot") {
                        try? await Task.sleep(for: .seconds(1))
                        app.runAutopilot()
                    }
                }
        }
        .modelContainer(container)
    }
}
