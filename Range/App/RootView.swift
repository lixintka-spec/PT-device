import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(HingeEngine.self) private var hinge
    @Environment(SessionEngine.self) private var session
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppState.Tab.today) { TodayView() }
            Tab("Session", systemImage: "gauge.with.needle.fill", value: AppState.Tab.session) { SessionScreen() }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppState.Tab.progress) { ProgressScreen() }
            Tab("Care Team", systemImage: "stethoscope", value: AppState.Tab.care) { CareTeamScreen() }
        }
        .tint(RangeTheme.mint)
        // iPhone Duo: live hinge angle + status drive the whole experience.
        .onHingeChange { _, newContext in
            hinge.ingest(newContext)
        }
        .onChange(of: hinge.isPhysicallyClosed) { _, closed in
            handleHinge(closed: closed)
        }
        .overlay {
            if hinge.status == .closed, app.showOuterSummary, let summary = app.lastSummary, let maria = primary.first {
                OuterSummaryView(summary: summary, patient: maria)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: app.showOuterSummary)
        .sheet(isPresented: $app.showPlacementGuide) { PlacementGuideView() }
        .sheet(isPresented: $app.showDemoControls) { DemoControlsView() }
        .sheet(isPresented: $app.showPaywall) { PaywallScreen() }
        .onAppear {
            app.primaryPatient = primary.first
            if let maria = primary.first, session.phase == .ready { session.configure(for: maria) }
        }
        .onChange(of: primary.first?.id) {
            app.primaryPatient = primary.first
            if let maria = primary.first, session.phase == .ready { session.configure(for: maria) }
        }
    }

    /// Close-to-save: closing the phone ends the session; the replay plays on the outer display.
    private func handleHinge(closed: Bool) {
        if closed {
            // Only a session that has started measuring gets saved; positioning just waits.
            if [.matchLastBest, .reps, .holding].contains(session.phase) {
                if let s = session.finish(patient: primary.first, context: context) {
                    app.lastSummary = s
                    app.showOuterSummary = true
                }
            } else if session.phase == .complete, app.lastSummary != nil {
                app.showOuterSummary = true
            }
        } else {
            app.showOuterSummary = false
        }
    }
}

/// The outer display after closing: saved, and the joint regains its range day by day.
struct OuterSummaryView: View {
    var summary: SessionSummary
    var patient: Patient

    var body: some View {
        ZStack {
            RangeTheme.backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Chip(text: "Saved · sent to Dr. Kim", systemImage: "checkmark.seal.fill", tint: RangeTheme.mint)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(summary.peak.rounded()))°").font(RangeTheme.numeral(52, weight: .bold))
                        if summary.gain > 0.5 {
                            Text("+\(Int(summary.gain.rounded()))°").font(RangeTheme.numeral(24, weight: .bold)).foregroundStyle(RangeTheme.mint)
                        }
                    }
                    if summary.beyondNoise {
                        Text("Beyond measurement error — real progress.").font(.subheadline.weight(.semibold)).foregroundStyle(RangeTheme.mint)
                    }
                    if let m = summary.milestone {
                        Label("Unlocked: \(m.title)", systemImage: m.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RangeTheme.amber)
                    }
                    RecoveryReplayView(patient: patient, compact: true)
                        .frame(minHeight: 330)
                        .padding(14)
                        .rangePanel()
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
        }
    }
}
