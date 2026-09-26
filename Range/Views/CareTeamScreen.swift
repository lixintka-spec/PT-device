import SwiftUI
import SwiftData
import RevenueCat
import RevenueCatUI

struct CareTeamScreen: View {
    @Environment(ProStore.self) private var store
    @Environment(AppState.self) private var app

    var body: some View {
        if store.isClinicUnlocked {
            ClinicDashboard()
        } else {
            ClinicLockedView()
        }
    }
}

struct ClinicLockedView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                ScrollView {
                    VStack(spacing: 22) {
                        Image(systemName: "stethoscope.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(RangeTheme.mint)
                        Text("Range Clinic").font(.largeTitle.bold())
                        Text("See every patient's range the moment they finish a session.")
                            .font(.title3)
                            .foregroundStyle(RangeTheme.secondaryText)
                            .multilineTextAlignment(.center)
                        VStack(alignment: .leading, spacing: 14) {
                            FeatureRow(symbol: "dot.radiowaves.left.and.right", title: "Live sessions", detail: "Reps and peaks arrive as patients move.")
                            FeatureRow(symbol: "exclamationmark.triangle.fill", title: "Stiffness alerts", detail: "Catch plateaus before the 6-week window closes.")
                            FeatureRow(symbol: "text.page.fill", title: "AI progress notes", detail: "Drafted on-device from session data. You sign.")
                            FeatureRow(symbol: "calendar.badge.checkmark", title: "RTM billing tracker", detail: "Counts the 16 data days per 30 you need to bill.")
                        }
                        .padding(20)
                        .rangePanel()
                        Button {
                            app.showPaywall = true
                        } label: {
                            Text("Start free trial").font(.headline).frame(maxWidth: 360).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RangeTheme.mint)
                        .foregroundStyle(.black)
                    }
                    .frame(maxWidth: 560)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Care Team")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeatureRow: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(RangeTheme.mint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(RangeTheme.secondaryText)
            }
        }
    }
}

struct ClinicDashboard: View {
    @Query private var patients: [Patient]
    @State private var selection: Patient.ID?
    @Environment(ProStore.self) private var store
    @State private var showCustomerCenter = false
    @State private var showAssessment = false

    private var sorted: [Patient] {
        patients.sorted { a, b in
            if a.isLive != b.isLive { return a.isLive }
            if a.risk != b.risk { return a.risk > b.risk }
            return a.name < b.name
        }
    }

    var body: some View {
        NavigationSplitView {
            List(sorted, selection: $selection) { patient in
                PatientRow(patient: patient)
                    .tag(patient.id)
            }
            .navigationTitle("Patients")
            .toolbar {
                ToolbarOverflowMenu {
                    if store.isConfigured {
                        Button { showCustomerCenter = true } label: { Label("Manage Subscription", systemImage: "creditcard") }
                    } else {
                        Button { store.demoLock() } label: { Label("Lock Clinic (demo)", systemImage: "lock") }
                    }
                }
            }
        } detail: {
            if let id = selection ?? sorted.first?.id, let patient = patients.first(where: { $0.id == id }) {
                PatientDetailView(patient: patient, showAssessment: $showAssessment)
            } else {
                ContentUnavailableView("Select a patient", systemImage: "person.crop.circle")
            }
        }
        .sheet(isPresented: $showCustomerCenter) { CustomerCenterView() }
        .sheet(isPresented: $showAssessment) { CameraAssessmentView() }
    }
}

extension Patient {
    /// A session finished in the last 15 minutes — shows live on the dashboard.
    var isLive: Bool {
        guard let last = lastSession else { return false }
        return Date.now.timeIntervalSince(last.date) < 15 * 60
    }
}

struct PatientRow: View {
    var patient: Patient
    var body: some View {
        HStack(spacing: 12) {
            Text(patient.initials)
                .font(.headline)
                .frame(width: 42, height: 42)
                .background(patient.risk.tint.opacity(0.2), in: .circle)
                .foregroundStyle(patient.risk.tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(patient.name).font(.headline)
                    if patient.isLive {
                        LiveDot()
                    }
                }
                Text("Day \(patient.dayToday) · \(patient.side.short) \(patient.joint.title.lowercased()) · \(Int(patient.bestFlexion))°")
                    .font(.subheadline)
                    .foregroundStyle(RangeTheme.secondaryText)
            }
            Spacer()
            Image(systemName: patient.risk.symbol).foregroundStyle(patient.risk.tint)
        }
        .padding(.vertical, 4)
    }
}

struct LiveDot: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(RangeTheme.mint).frame(width: 7, height: 7).opacity(on ? 1 : 0.3)
            Text("Live").font(.caption2.weight(.bold)).foregroundStyle(RangeTheme.mint)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { on = true } }
    }
}

struct PatientDetailView: View {
    var patient: Patient
    @Binding var showAssessment: Bool
    @State private var note: String = ""
    @State private var generating = false
    @State private var noteSource = ""

    var body: some View {
        ZStack {
            RangeTheme.backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(patient.name).font(.largeTitle.bold())
                        Text("\(patient.age) · \(patient.procedure) · \(patient.side.title) \(patient.joint.title.lowercased()) · Week \(patient.weekToday)")
                            .foregroundStyle(RangeTheme.secondaryText)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: patient.risk.symbol).font(.title2).foregroundStyle(patient.risk.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(patient.risk.title).font(.headline).foregroundStyle(patient.risk.tint)
                            Text(patient.riskDetail).font(.subheadline)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(patient.risk.tint.opacity(0.10), in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(patient.risk.tint.opacity(0.35)))

                    HStack {
                        StatTile(title: "Best", value: "\(Int(patient.bestFlexion))°", detail: "flexion", tint: RangeTheme.mint)
                        StatTile(title: "Extension", value: "−\(Int(patient.extensionDeficit))°", detail: "deficit", tint: RangeTheme.sky)
                        StatTile(title: "Pain", value: "\(patient.lastSession?.pain ?? 0)/10", detail: "last session", tint: RangeTheme.amber)
                        RTMTile(days: patient.rtmDays)
                    }

                    RecoveryChart(patient: patient)
                        .padding(18)
                        .rangePanel()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Progress note", systemImage: "text.page.fill").font(.headline)
                            Spacer()
                            if !noteSource.isEmpty { Chip(text: noteSource, systemImage: "lock.shield", tint: RangeTheme.sky) }
                        }
                        if note.isEmpty {
                            Text("Draft a SOAP note from this patient's session data. Review before signing.")
                                .font(.subheadline)
                                .foregroundStyle(RangeTheme.secondaryText)
                        } else {
                            Text(note)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        HStack {
                            Button {
                                Task {
                                    generating = true
                                    let result = await NoteGenerator.draft(for: patient)
                                    note = result.text
                                    noteSource = result.source
                                    generating = false
                                }
                            } label: {
                                Label(generating ? "Drafting…" : (note.isEmpty ? "Draft note" : "Redraft"), systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RangeTheme.sky)
                            .disabled(generating)
                            if !note.isEmpty {
                                ShareLink(item: note) { Label("Share", systemImage: "square.and.arrow.up") }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(18)
                    .rangePanel()
                }
                .padding(24)
            }
        }
        .navigationTitle(patient.firstName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAssessment = true } label: { Label("Camera Assessment", systemImage: "camera.viewfinder") }
            }
        }
        .onChange(of: patient.id) { note = ""; noteSource = "" }
    }
}

struct RTMTile: View {
    var days: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RTM days").font(.caption.weight(.semibold)).foregroundStyle(RangeTheme.secondaryText)
            Text("\(days)/\(Clinical.rtmRequiredDays)").font(RangeTheme.numeral(28, weight: .bold))
                .foregroundStyle(days >= Clinical.rtmRequiredDays ? RangeTheme.mint : RangeTheme.amber)
            ProgressView(value: min(1, Double(days) / Double(Clinical.rtmRequiredDays)))
                .tint(days >= Clinical.rtmRequiredDays ? RangeTheme.mint : RangeTheme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .rangePanel(cornerRadius: 18)
    }
}
