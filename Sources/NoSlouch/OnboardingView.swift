import SwiftUI

struct OnboardingView: View {
  @ObservedObject var viewModel: PostureViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Welcome to NoSlouch")
        .font(.title)
        .bold()
      Text("Posture & desk-wellness for Mac. A quick, three-step setup:")
        .foregroundStyle(.secondary)

      Label("Put on your AirPods and set them as the Mac's audio output.", systemImage: "airpods")
      Label("Allow notifications so NoSlouch can nudge you.", systemImage: "bell")
      Label("Sit up straight, then Calibrate to set your baseline.", systemImage: "figure.stand")

      if !viewModel.notificationsEnabled {
        Button("Enable Notifications") {
          viewModel.requestNotifications()
        }
      }

      Button(viewModel.isMonitoring ? "Recheck Headphones" : "Connect and Start") {
        if viewModel.isMonitoring { viewModel.retryMotion() } else { viewModel.startMonitoring() }
      }
      Text(viewModel.statusText).font(.callout)
      Text(viewModel.diagnosticsText).font(.caption).foregroundStyle(.secondary)
      Button("Open Motion Settings") { viewModel.openMotionSettings() }
      Button("Calibrate Upright Position") { viewModel.beginGuidedCalibration() }
        .disabled(viewModel.isCalibrating)
      Text(viewModel.calibrationMessage).font(.callout)
        .accessibilityLabel(viewModel.calibrationMessage)
      if viewModel.isCalibrating {
        Button("Cancel Calibration") { viewModel.cancelCalibration() }
      }
      Toggle(
        "Start monitoring automatically when NoSlouch opens",
        isOn: Binding(
          get: { viewModel.settings.startMonitoringAtLaunch },
          set: { viewModel.updateStartMonitoringAtLaunch($0) }))
      Spacer()

      HStack {
        Spacer()
        Button("Get Started") {
          viewModel.completeOnboarding()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460, height: 560)
  }
}
