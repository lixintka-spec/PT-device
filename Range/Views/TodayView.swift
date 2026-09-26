import SwiftUI
import SwiftData
import Charts

/// The first thing Maria sees — on the outer display when closed, expanded on the inner display.
struct TodayView: View {
    @Environment(AppState.self) private var app
    @Environment(SessionEngine.self) private var session
    @Environment(\.horizontalSizeClass) private var hSize
    @Query(filter: #Predicate<Patient> { $0.isPrimary }) private var primary: [Patient]

    var body: some View {
        NavigationStack {
            ZStack {
                RangeTheme.backdrop
                if let maria = primary.first {
                    if hSize == .compact {
                        ScrollView { TodayCard(patient: maria, compact: true).padding(16) }
                    } else {
                        ArrangementView {
                            ScrollView { TodayCard(patient: maria, compact: false).padding(24) }
                        } secondary: {
                            ScrollView { WeekPanel(patient: maria).padding(24) }
                        }
                        .arrangementViewStyle(.split.axes(.horizontal))
                    }
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { app.showPlacementGuide = true } label: { Label("How to Wear", systemImage: "figure.stand") }
                }
                ToolbarOverflowMenu {
                    Button { app.showDemoControls = true } label: { Label("Demo Controls", systemImage: "slider.horizontal.3") }
                }
            }
        }
    }
}

struct TodayCard: View {
    var patient: Patient
    var compact: Bool
    @Environment(AppState.self) private var app
    @Environment(SessionEngine.self) private var session

    private var doneToday: RehabSession? {
        patient.sortedSessions.last(where: { $0.date >= Calendar.current.startOfDay(for: .now) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            HStack {
                Chip(text: "Day \(patient.dayToday) after surgery", systemImage: "calendar", tint: RangeTheme.sky)
                Spacer()
                Chip(text: "\(patient.streak)-day streak", systemImage: "flame.fill", tint: RangeTheme.amber)
            }
            Text("Hi \(patient.firstName)")
                .font(compact ? .title.bold() : .largeTitle.bold())

            HStack(alignment: .center, spacing: compact ? 12 : 20) {
                MiniGauge(best: doneToday?.peakFlexion ?? patient.bestBeforeToday,
                          target: patient.adaptiveTarget, done: doneToday != nil)
                    .frame(width: compact ? 120 : 170, height: compact ? 78 : 108)
                VStack(alignment: .leading, spacing: 4) {
                    if let done = doneToday {
                        Text("Done today").font(.caption.weight(.semibold)).foregroundStyle(RangeTheme.mint)
                        Text("\(Int(done.peakFlexion))°").font(RangeTheme.numeral(compact ? 34 : 44, weight: .bold))
                        Text("+\(Int(done.peakFlexion - patient.bestBeforeToday))° vs last best")
                            .font(.subheadline).foregroundStyle(RangeTheme.secondaryText)
                    } else {
                        Text("Last best").font(.caption.weight(.semibold)).foregroundStyle(RangeTheme.secondaryText)
                        Text("\(Int(patient.bestBeforeToday))°").font(RangeTheme.numeral(compact ? 34 : 44, weight: .bold))
                        Text("Today: \(Int(patient.adaptiveTarget))°")
                            .font(.headline).foregroundStyle(RangeTheme.amber)
                    }
                }
            }

            if doneToday == nil {
                Text("Your comfortable max is \(Int(patient.comfortableMax))°. Let's aim for \(Int(patient.adaptiveTarget))° today.")
                    .font(compact ? .subheadline : .title3)
                    .foregroundStyle(RangeTheme.secondaryText)
            }

            if let next = patient.nextMilestone {
                HStack(spacing: 10) {
                    Image(systemName: next.symbol).font(.title3).foregroundStyle(RangeTheme.amber)
                        .frame(width: 34, height: 34).background(RangeTheme.amber.opacity(0.14), in: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next milestone").font(.caption).foregroundStyle(RangeTheme.secondaryText)
                        Text("\(next.title) · \(Int(next.degrees))°").font(.subheadline.weight(.semibold))
                    }
                }
            }

            Button {
                session.configure(for: patient)
                app.tab = .session
                session.begin()
            } label: {
                Label(doneToday == nil ? "Start session" : "Another set", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 2 : 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(RangeTheme.mint)
            .foregroundStyle(.black)
        }
        .padding(compact ? 16 : 22)
        .rangePanel(cornerRadius: 26)
    }
}

/// Half-dial showing last best and today's target.
struct MiniGauge: View {
    var best: Double
    var target: Double
    var done: Bool
    var body: some View {
        Canvas { ctx, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height - 4)
            let r = min(size.width / 2, size.height) - 8
            func p(_ d: Double, _ rr: CGFloat) -> CGPoint { LimbPainter.point(pivot, 180 - d * 180 / 140, rr) }
            var base = Path()
            for d in stride(from: 0.0, through: 140, by: 2) { d == 0 ? base.move(to: p(d, r)) : base.addLine(to: p(d, r)) }
            ctx.stroke(base, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            var fill = Path()
            for d in stride(from: 0.0, through: min(140, best), by: 1) { d == 0 ? fill.move(to: p(d, r)) : fill.addLine(to: p(d, r)) }
            ctx.stroke(fill, with: .color(done ? RangeTheme.mint : RangeTheme.sky), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            var t = Path()
            t.move(to: p(target, r - 12))
            t.addLine(to: p(target, r + 10))
            ctx.stroke(t, with: .color(RangeTheme.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .accessibilityLabel("Best \(Int(best)) degrees, target \(Int(target)) degrees")
    }
}

struct WeekPanel: View {
    var patient: Patient
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This week").font(.title2.bold())
            Chart(patient.sortedSessions.suffix(7), id: \.id) { s in
                BarMark(x: .value("Day", "D\(patient.day(of: s.date))"),
                        yStart: .value("Base", 40), yEnd: .value("Flexion", s.peakFlexion))
                    .foregroundStyle(RangeTheme.mint.gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        Text("\(Int(s.peakFlexion))").font(.caption2).foregroundStyle(RangeTheme.secondaryText)
                    }
            }
            .chartYScale(domain: 40...120)
            .frame(height: 180)
            .padding(16)
            .rangePanel()

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "stethoscope")
                    .font(.title3)
                    .foregroundStyle(RangeTheme.sky)
                    .frame(width: 40, height: 40)
                    .background(RangeTheme.sky.opacity(0.14), in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dr. Kim · your PT").font(.subheadline.weight(.semibold))
                    Text("Great week, \(patient.firstName). Keep the holds slow — straightening fully matters as much as bending.")
                        .font(.subheadline)
                        .foregroundStyle(RangeTheme.secondaryText)
                }
            }
            .padding(16)
            .rangePanel()

            HStack {
                StatTile(title: "Extension", value: "−\(Int(patient.extensionDeficit))°", detail: "from straight", tint: RangeTheme.sky)
                StatTile(title: "Comfortable", value: "\(Int(patient.comfortableMax))°", detail: "median of 3", tint: RangeTheme.mint)
            }
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var detail: String
    var tint: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(RangeTheme.secondaryText)
            Text(value).font(RangeTheme.numeral(28, weight: .bold)).foregroundStyle(tint)
            Text(detail).font(.caption2).foregroundStyle(RangeTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .rangePanel(cornerRadius: 18)
    }
}
