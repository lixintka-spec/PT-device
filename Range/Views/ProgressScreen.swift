import SwiftUI
import SwiftData
import Charts

struct ProgressScreen: View {
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                if let maria = primary.first {
                    ArrangementView {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                RecoveryReplayView(patient: maria)
                                    .padding(18)
                                    .rangePanel()
                                RecoveryChart(patient: maria)
                                    .padding(18)
                                    .rangePanel()
                            }
                            .padding(20)
                        }
                    } secondary: {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                MilestoneLadder(patient: maria)
                                    .padding(18)
                                    .rangePanel()
                                HStack {
                                    StatTile(title: "Best", value: "\(Int(maria.bestFlexion))°", detail: "knee flexion", tint: RangeTheme.mint)
                                    StatTile(title: "Gained", value: "+\(Int(maria.gainSinceFirstSession))°", detail: "since day 1", tint: RangeTheme.sky)
                                }
                                HStack {
                                    StatTile(title: "Streak", value: "\(maria.streak)", detail: "days in a row", tint: RangeTheme.amber)
                                    StatTile(title: "Sessions", value: "\(maria.sessions.count)", detail: "since surgery")
                                }
                            }
                            .padding(20)
                        }
                    }
                    .arrangementViewStyle(.split)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { app.tab = .exercise } label: { Label("New Session", systemImage: "play.fill") }
                }
            }
        }
    }
}

/// How far the knee bends, day by day.
struct RecoveryChart: View {
    var patient: Patient
    var showsHeader = true

    var body: some View {
        let sessions = patient.sortedSessions
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack {
                    Text("Knee bend over time").font(.headline)
                    Spacer()
                    Chip(text: "+\(Int(patient.gainSinceFirstSession))° since day 1", systemImage: "arrow.up.right", tint: RangeTheme.mint)
                }
            }
            Chart {
                ForEach(sessions, id: \.id) { s in
                    AreaMark(x: .value("Day", patient.day(of: s.date)), yStart: .value("Base", 40), yEnd: .value("Flexion", s.peakFlexion))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [RangeTheme.mint.opacity(0.35), RangeTheme.mint.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                }
                if let next = patient.nextMilestone {
                    RuleMark(y: .value("Next milestone", next.degrees))
                        .foregroundStyle(RangeTheme.amber.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Label("Next: \(next.title) · \(Int(next.degrees))°", systemImage: next.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RangeTheme.amber)
                        }
                }
                ForEach(sessions, id: \.id) { s in
                    LineMark(x: .value("Day", patient.day(of: s.date)), y: .value("Flexion", s.peakFlexion))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(RangeTheme.mint)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Day", patient.day(of: s.date)), y: .value("Flexion", s.peakFlexion))
                        .foregroundStyle(s.date >= Calendar.current.startOfDay(for: .now) ? RangeTheme.amber : RangeTheme.mint)
                        .symbolSize(s.date >= Calendar.current.startOfDay(for: .now) ? 110 : 26)
                }
            }
            .chartYScale(domain: 40...130)
            .chartXAxisLabel("Day of recovery")
            .frame(height: 240)
        }
    }
}

struct MilestoneLadder: View {
    var patient: Patient
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Getting life back").font(.headline)
            ForEach(patient.joint.milestones.reversed()) { m in
                let reached = patient.bestFlexion >= m.degrees
                let isNext = patient.nextMilestone == m
                HStack(spacing: 12) {
                    Image(systemName: m.symbol)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background((reached ? RangeTheme.mint : (isNext ? RangeTheme.amber : Color.white)).opacity(reached || isNext ? 0.18 : 0.06), in: .circle)
                        .foregroundStyle(reached ? RangeTheme.mint : (isNext ? RangeTheme.amber : RangeTheme.tertiaryText))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(reached || isNext ? .white : RangeTheme.secondaryText)
                        Text(reached ? "Unlocked" : (isNext ? "\(Int(m.degrees - patient.bestFlexion))° to go" : "~\(Int(m.degrees))°"))
                            .font(.caption)
                            .foregroundStyle(reached ? RangeTheme.mint : RangeTheme.tertiaryText)
                    }
                    Spacer()
                    Text("\(Int(m.degrees))°").font(RangeTheme.numeral(15, weight: .semibold)).foregroundStyle(RangeTheme.secondaryText)
                }
            }
            Text("Approximate range needed for each activity.")
                .font(.caption2)
                .foregroundStyle(RangeTheme.tertiaryText)
        }
    }
}
