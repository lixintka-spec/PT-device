import SwiftUI
import SwiftData

/// Stage controls for recording the demo in the Simulator.
struct DemoControlsView: View {
    @Environment(HingeEngine.self) private var hinge
    @Environment(Leveler.self) private var leveler
    @Environment(SessionEngine.self) private var session
    @Environment(ProStore.self) private var store
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var manualAngle: Double = 180

    var body: some View {
        @Bindable var leveler = leveler
        @Bindable var app = app
        NavigationStack {
            Form {
                Section("Hinge") {
                    LabeledContent("Status", value: hinge.status.title)
                    LabeledContent("Hinge angle", value: "\(Int(hinge.angle.rounded()))°")
                    LabeledContent("Flexion", value: "\(Int(hinge.flexion.rounded()))°")
                    LabeledContent("Source", value: hinge.isAutopilot ? "Autopilot" : (hinge.hasHardwareHinge ? "iPhone Duo hinge" : "No hinge — use slider"))
                    if !hinge.hasHardwareHinge || hinge.isAutopilot {
                        VStack(alignment: .leading) {
                            Text("Manual hinge: \(Int(manualAngle))°")
                            Slider(value: $manualAngle, in: 0...180, step: 1)
                                .onChange(of: manualAngle) { _, v in hinge.ingest(degrees: v) }
                        }
                    }
                }
                Section {
                    VStack(alignment: .leading) {
                        Text("Simulated tilt: \(Int(leveler.simulatedTilt))°")
                        Slider(value: $leveler.simulatedTilt, in: -20...20, step: 1)
                    }
                    Toggle("Settle to level automatically", isOn: $leveler.autoSettle)
                } header: {
                    Text("Leveler")
                } footer: {
                    Text(leveler.isSimulated ? "The Simulator has no motion sensors; this drives the leveler." : "Using Core Motion (device motion body = the session view).")
                }
                Section {
                    Button {
                        dismiss()
                        app.runAutopilot()
                    } label: {
                        Label("Run Full Demo (Autopilot)", systemImage: "play.rectangle.fill")
                    }
                    Button { hinge.isAutopilot = false } label: { Label("Stop Autopilot", systemImage: "stop.fill") }
                } footer: {
                    Text("Autopilot drives the hinge inside the app for tools that can't script the Simulator hinge (e.g. Bitrig). With Xcode's Device Hub, prefer scripts/demo.sh — it moves the real simulated hinge.")
                }
                Section("Data") {
                    Button {
                        SeedData.reset(context)
                        session.reset()
                        app.lastSummary = nil
                    } label: { Label("Reset Demo Data", systemImage: "arrow.counterclockwise.circle") }
                    Toggle("Mute voice & tones", isOn: $app.isMuted)
                }
                Section("Range Clinic") {
                    LabeledContent("RevenueCat", value: store.isConfigured ? "Configured" : "Demo mode (no API key)")
                    LabeledContent("Clinic entitlement", value: store.isClinicUnlocked ? "Active" : "Locked")
                    if store.isDemoMode {
                        Button { store.demoLock() } label: { Label("Lock Clinic", systemImage: "lock") }
                    }
                }
            }
            .navigationTitle("Demo Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
        .onAppear { manualAngle = hinge.rawAngle }
    }
}

struct PlacementGuideView: View {
    @Environment(SessionEngine.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var flex: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LimbFigure(flexion: flex, joint: session.exercise.joint, showScale: true)
                            .frame(height: 260)
                            .task {
                                while !Task.isCancelled {
                                    withAnimation(.easeInOut(duration: 1.6)) { flex = 95 }
                                    try? await Task.sleep(for: .seconds(2.2))
                                    withAnimation(.easeInOut(duration: 1.6)) { flex = 0 }
                                    try? await Task.sleep(for: .seconds(2.2))
                                }
                            }
                        Text(session.exercise.placement).font(.title3.weight(.semibold))
                        StepRow(number: 1, title: "Fold on the crease", detail: "Line the phone's hinge up with the joint line.")
                        StepRow(number: 2, title: "Strap both halves", detail: "One strap above the joint, one below. Snug, not tight.")
                        StepRow(number: 3, title: "Same spot every day", detail: "Consistency beats absolute accuracy — it makes day-to-day change trustworthy.")
                        StepRow(number: 4, title: "Screen faces away? That's fine", detail: "Tones, taps and a voice coach you, eyes-free.")
                    }
                    .padding(24)
                    .frame(maxWidth: 640)
                }
            }
            .navigationTitle("How to Wear Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Label("Done", systemImage: "checkmark") }
                }
            }
        }
    }
}
