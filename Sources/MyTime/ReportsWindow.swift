import SwiftUI
import AppKit

struct ReportsView: View {
    let journal: Journal
    @State private var period: ReportPeriod = .week
    @State private var grouping: ReportGrouping = .client
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var result: ReportResult = ReportResult(rows: [], totalEntries: 0, totalSeconds: 0, discardedSeconds: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Group By", selection: $grouping) {
                    ForEach(ReportGrouping.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 220)
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 200)
                if period == .custom {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
                Button("Refresh", action: compute)
            }

            HStack(alignment: .top, spacing: 16) {
                Table(result.rows) {
                    TableColumn("Group") { row in
                        HStack(spacing: 6) {
                            Circle().fill(PieChart.color(for: row.group)).frame(width: 10, height: 10)
                            Text(row.group)
                        }
                    }
                    TableColumn("Duration") { row in Text(Reports.formatHMS(row.seconds)) }
                    TableColumn("Percent") { row in Text(String(format: "%.1f%%", row.percent * 100)) }
                    TableColumn("Share") { row in
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.secondary.opacity(0.15))
                                Rectangle().fill(PieChart.color(for: row.group)).frame(width: geo.size.width * CGFloat(row.percent))
                            }.cornerRadius(3)
                        }.frame(height: 14)
                    }
                }
                .frame(minWidth: 420)

                PieChart(rows: result.rows)
                    .frame(width: 240, height: 240)
                    .padding(.top, 4)
            }

            HStack {
                Text("Entries: \(result.totalEntries)")
                Spacer()
                Text("Total: \(Reports.formatHMS(result.totalSeconds))")
            }.font(.callout).foregroundColor(.secondary)
        }
        .padding(16)
        .onAppear { compute() }
        .onChange(of: period) { _ in compute() }
        .onChange(of: grouping) { _ in compute() }
        .onChange(of: customStart) { _ in if period == .custom { compute() } }
        .onChange(of: customEnd) { _ in if period == .custom { compute() } }
    }

    private func compute() {
        let entries = journal.readAll()
        result = Reports.compute(entries: entries, period: period, grouping: grouping,
                                 customStart: customStart, customEnd: customEnd)
    }
}

// MARK: - Pie chart

struct PieChart: View {
    let rows: [ReportRow]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let total = rows.reduce(0.0) { $0 + $1.percent }

            ZStack {
                if total <= 0 {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    Text("No data")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(slices().enumerated()), id: \.offset) { _, slice in
                        Path { p in
                            p.move(to: center)
                            p.addArc(center: center,
                                     radius: radius,
                                     startAngle: slice.start,
                                     endAngle: slice.end,
                                     clockwise: false)
                            p.closeSubpath()
                        }
                        .fill(Self.color(for: slice.label))
                    }
                    Circle()
                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                        .frame(width: side, height: side)
                        .position(center)
                }
            }
        }
    }

    private struct Slice {
        let label: String
        let start: Angle
        let end: Angle
    }

    private func slices() -> [Slice] {
        var result: [Slice] = []
        var cursor = Angle.degrees(-90) // start at 12 o'clock
        let total = rows.reduce(0.0) { $0 + $1.percent }
        guard total > 0 else { return [] }
        for row in rows {
            let sweep = Angle.degrees(360 * row.percent / total)
            let end = cursor + sweep
            result.append(Slice(label: row.group, start: cursor, end: end))
            cursor = end
        }
        return result
    }

    /// Deterministic color per group label so the legend (table) and pie agree.
    static func color(for label: String) -> Color {
        let palette: [Color] = [
            .blue, .orange, .green, .pink, .purple, .teal, .yellow, .red,
            .mint, .indigo, .cyan, .brown
        ]
        var hash: UInt64 = 1469598103934665603
        for byte in label.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

final class ReportsWindowController {
    private var window: NSWindow?
    let journal: Journal
    init(journal: Journal) { self.journal = journal }

    func show() {
        if let w = window {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let view = ReportsView(journal: journal)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "MyTime Reports"
        w.setContentSize(NSSize(width: 800, height: 600))
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.collectionBehavior.insert(.moveToActiveSpace)
        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
