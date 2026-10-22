import SwiftUI
import Charts

struct ChartView: View {
    let data: [DailySummary]
    let range: TimeRange

    @State private var hoveredLabel: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Keystrokes")
                .font(.headline)
                .padding(.bottom, 4)

            if data.isEmpty {
                Text("Use your Mac for a few days to see trends")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(data, id: \.date) { item in
                    let value = Double(item.keystrokes)

                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(Color.blue.opacity(0.15))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(30)

                    if hoveredLabel == item.date {
                        RuleMark(x: .value("Date", item.date))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .annotation(position: .top, spacing: 4) {
                                Text("\(Int(value))")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(4)
                            }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let dateStr = value.as(String.self) {
                                Text(formatLabel(from: dateStr))
                            }
                        }
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Keystrokes chart for \(range == .week ? "this week" : range == .month ? "this month" : "this year")")
                .chartYAxisLabel("Keystrokes")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let origin = geometry[proxy.plotFrame!].origin
                                    let x = location.x - origin.x
                                    if let label: String = proxy.value(atX: x) {
                                        hoveredLabel = label
                                    }
                                case .ended:
                                    hoveredLabel = nil
                                }
                            }
                    }
                }
            }
        }
    }

    private func formatLabel(from dateString: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return dateString }

        let display = DateFormatter()
        switch range {
        case .week:
            display.dateFormat = "EEE"
        case .month:
            display.dateFormat = "d"
        case .year:
            display.dateFormat = "MMM d"
        }
        return display.string(from: date)
    }
}

#Preview {
    ChartView(
        data: [
            DailySummary(date: "2025-01-10", keystrokes: 2000),
            DailySummary(date: "2025-01-11", keystrokes: 3000),
            DailySummary(date: "2025-01-12", keystrokes: 1500)
        ],
        range: .week
    )
    .frame(height: 250)
    .padding()
}
