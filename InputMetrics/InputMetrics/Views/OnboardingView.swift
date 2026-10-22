import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var currentStep = 0
    var onComplete: () -> Void

    private let steps: [(icon: String, title: String, description: String)] = [
        ("keyboard", "Track Your Input",
         "InputMetrics runs in your menu bar and tracks your keyboard usage."),
        ("lock.shield", "Permissions Required",
         "All data stays on your device. InputMetrics needs the Input Monitoring permission to track keyboard usage.\n\nGrant it in System Settings > Privacy & Security."),
        ("chart.bar.xaxis", "View Your Stats",
         "Click the menu bar icon to see today's activity. Open the dashboard for detailed charts and heatmaps."),
        ("gearshape", "Customize",
         "Configure data retention and export your data from Settings.")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: steps[currentStep].icon)
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text(steps[currentStep].title)
                .font(.title.bold())

            Text(steps[currentStep].description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if currentStep == 1 {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.blue : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(currentStep + 1) of \(steps.count)")

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if currentStep < steps.count - 1 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(width: 450, height: 420)
    }
}
