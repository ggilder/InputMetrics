import SwiftUI
import AppKit
import Charts

struct MenuBarView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @State private var viewModel = MenuBarViewModel()
    @State private var hoveredKeyboardLabel: String?
    @State private var showKeyboardWarning = false
    @State private var dataRefreshTick = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    WindowManager.shared.openSettingsWindow()
                }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Settings")

                Spacer()

                Text("Keyboard Metrics")
                    .font(.headline)

                Spacer()

                Button(action: {
                    WindowManager.shared.openDashboardWindow()
                }) {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityLabel("Dashboard")
            }
            .padding()

            ScrollView {
                VStack(spacing: 16) {
                    if showKeyboardWarning {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keyboard tracking requires Input Monitoring permission")
                                    .font(.caption.bold())
                                Button("Open System Settings") {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.link)
                            }

                            Spacer()

                            Button {
                                showKeyboardWarning = false
                                preferences.dismissedKeyboardPermissionWarning = true
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss")
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    // Today's Activity Header
                    Text("Today's Activity")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    // Active Time Card
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.title3)
                            .foregroundStyle(.teal)

                        if let range = viewModel.formattedActiveTimeRange {
                            Text(range)
                                .font(.headline.monospacedDigit())
                        } else {
                            Text("Activity tracking will begin as you use your Mac")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Active Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    if UserPreferences.shared.goalConfig.enabled {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Goals")
                                    .font(.headline)
                                Spacer()
                                if viewModel.currentStreak > 0 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "flame.fill")
                                            .foregroundStyle(.orange)
                                        Text("\(viewModel.currentStreak) day streak")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: "keyboard")
                                        .foregroundStyle(.purple)
                                    ProgressView(value: viewModel.keystrokeProgress)
                                        .tint(.purple)
                                        .accessibilityLabel("Keystroke goal progress")
                                        .accessibilityValue("\(Int(viewModel.keystrokeProgress * 100)) percent")
                                    Text("\(Int(viewModel.keystrokeProgress * 100))%")
                                        .font(.caption)
                                        .monospacedDigit()
                                        .frame(width: 40, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    keyboardMetricsView

                    Divider()
                        .padding(.horizontal)

                    // All Time Stats
                    allTimeStatsView

                    // App Usage
                    VStack(alignment: .leading, spacing: 8) {
                        DisclosureGroup("App Usage") {
                            AppUsageView(entries: viewModel.appUsageEntries)
                                .padding(.top, 8)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(width: 420, height: 600)
        .onReceive(timer) { _ in
            viewModel.updateStats()
            viewModel.refreshAllTimeTotalsIfNeeded()
            viewModel.updateAllTimeStats()
            updateKeyboardWarning()
            viewModel.loadChartData()
            dataRefreshTick += 1
            if dataRefreshTick % 10 == 0 {
                viewModel.loadKeyboardData()
                viewModel.loadHourlySummaries()
                viewModel.loadAppUsage()
            }
        }
        .onAppear {
            viewModel.loadAll()
            updateKeyboardWarning()
        }
    }

    private var keyboardMetricsView: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Keystrokes Card
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundStyle(.purple)

                    Text("\(viewModel.keystrokes)")
                        .font(.title.bold())

                    Text("Keystrokes Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Keystrokes today: \(viewModel.keystrokes)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                // Active Time Card
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(.teal)

                    let hours = viewModel.activeMinutes / 60
                    let mins = viewModel.activeMinutes % 60
                    Text(hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m")
                        .font(.title.bold())

                    Text("Active Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Active time: \(viewModel.activeMinutes / 60) hours \(viewModel.activeMinutes % 60) minutes")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal)

            // Peak Typing Speed Card
            if viewModel.peakWPM > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "gauge.with.needle")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text(String(format: "%.0f WPM", viewModel.peakWPM))
                        .font(.title.bold())

                    Text("Peak Typing Speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Peak typing speed: \(String(format: "%.0f", viewModel.peakWPM)) words per minute")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Week Overview Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Week Overview")
                    .font(.headline)
                    .padding(.horizontal)

                if !viewModel.chartData.isEmpty {
                    Chart(viewModel.chartData.suffix(7), id: \.date) { item in
                        let label = viewModel.shortDay(from: item.date)
                        let count = item.keystrokes

                        LineMark(
                            x: .value("Day", label),
                            y: .value("Keystrokes", count)
                        )
                        .foregroundStyle(.purple)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Day", label),
                            y: .value("Keystrokes", count)
                        )
                        .foregroundStyle(.purple.opacity(0.1))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", label),
                            y: .value("Keystrokes", count)
                        )
                        .foregroundStyle(.purple)
                        .symbolSize(30)

                        if hoveredKeyboardLabel == label {
                            RuleMark(x: .value("Day", label))
                                .foregroundStyle(Color.secondary.opacity(0.3))
                                .annotation(position: .top, spacing: 4) {
                                    Text("\(count)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(4)
                                }
                        }
                    }
                    .frame(height: 150)
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
                                            hoveredKeyboardLabel = label
                                        }
                                    case .ended:
                                        hoveredKeyboardLabel = nil
                                    }
                                }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Weekly keystrokes chart")
                    .padding(.horizontal)
                } else {
                    Text("Use your Mac for a few days to see trends")
                        .foregroundStyle(.secondary)
                        .frame(height: 150)
                }
            }

            // Keyboard Heatmap
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup("Keyboard Heatmap") {
                    if !viewModel.keyboardEntries.isEmpty {
                        MiniKeyboardHeatmap(entries: viewModel.keyboardEntries)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Keyboard heatmap showing key usage frequency")
                            .frame(height: 150)
                            .padding(.top, 8)
                    } else {
                        Text("Start typing to see your keyboard heatmap")
                            .foregroundStyle(.secondary)
                            .frame(height: 100)
                    }
                }
                .padding(.horizontal)
            }

            // Hourly Breakdown
            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup("Hourly Breakdown") {
                    HourlyBreakdownView(hourlySummaries: viewModel.hourlySummaries)
                        .padding(.top, 8)
                }
                .padding(.horizontal)
            }

            // Top Keys
            VStack(alignment: .leading, spacing: 8) {
                Text("Most Used Keys")
                    .font(.headline)
                    .padding(.horizontal)

                if !viewModel.keyboardEntries.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(viewModel.topKeys, id: \.compositeId) { entry in
                            VStack(spacing: 4) {
                                Text(KeyCodeMapping.keyName(for: entry.keyCode))
                                    .font(.caption.bold())
                                Text("\(entry.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Text("Type to see your most used keys")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }

    private func updateKeyboardWarning() {
        let missing = EventMonitor.shared.isKeyboardPermissionLikelyMissing
        let dismissed = preferences.dismissedKeyboardPermissionWarning
        showKeyboardWarning = missing && !dismissed

        if !missing && preferences.dismissedKeyboardPermissionWarning {
            preferences.dismissedKeyboardPermissionWarning = false
        }
    }

    private var allTimeStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Time")
                .font(.title3.bold())
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Label("Keystrokes", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.allTimeKeystrokes)")
                    .font(.title2.bold().monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("All-time keystrokes: \(viewModel.allTimeKeystrokes)")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

#Preview {
    MenuBarView()
}
