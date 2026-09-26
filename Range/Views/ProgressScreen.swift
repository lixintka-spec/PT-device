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
                                    StatTile(title: "Extension", value: "−\(Int(maria.extensionDeficit))°", detail: "from straight", tint: RangeTheme.sky)
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
                    Button { app.tab = .session } label: { Label("New Session", systemImage: "play.fill") }
                }
            }
        }
    }
}

/// Flexion over time against the typical recovery band, with the measurement-noise band
/// so only real gains get celebrated.
struct RecoveryChart: View {
    var patient: Patient
    var showsHeader = true

    private struct BandPoint: Identifiable {
        let day: Int
        let low: Double
        let high: Double
        var id: Int { day }
    }

    var body: some View {
        let sessions = patient.sortedSessions
        let lastDay = max(patient.dayToday, sessions.last.map { patient.day(of: $0.date) } ?? 1)
        let band = stride(from: 0, through: lastDay + 3, by: 1).map { d -> BandPoint in
            let b = Clinical.expectedBand(joint: patient.joint, day: Double(d))
            return BandPoint(day: d, low: b.low, high: b.high)
        }
        let best = patient.bestFlexion
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                HStack {
                    Text("Flexion over time").font(.headline)
                    Spacer()
                    Chip(text: "±\(Int(Clinical.measurementNoise))° noise band", systemImage: "waveform.path", tint: RangeTheme.secondaryText)
                }
            }
            Chart {
                ForEach(band) { p in
                    AreaMark(x: .value("Day", p.day), yStart: .value("Low", p.low), yEnd: .value("High", p.high))
                        .foregroundStyle(.white.opacity(0.07))
                }
                RectangleMark(xStart: .value("Start", 0), xEnd: .value("End", lastDay + 3),
                              yStart: .value("Noise low", best - Clinical.measurementNoise),
                              yEnd: .value("Noise high", best + Clinical.measurementNoise))
                    .foregroundStyle(RangeTheme.mint.opacity(0.06))
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
            .chartXAxisLabel("Days since surgery")
            .frame(height: 240)
            Text("Grey band: typical range for this procedure (illustrative). Changes inside the mint band are within measurement error.")
                .font(.caption2)
                .foregroundStyle(RangeTheme.tertiaryText)
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
