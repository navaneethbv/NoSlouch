import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var viewModel: PostureViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("NoSlouch")
        .font(.headline)

      Text(viewModel.statusText)
        .foregroundStyle(viewModel.postureState == .bad ? .red : .secondary)

      if let pitch = viewModel.currentPitch {
        Text("Pitch: \(pitch, specifier: "%.1f") deg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let calibratedPitch = viewModel.lastCalibratedPitch {
        Text("Calibrated: \(calibratedPitch, specifier: "%.1f") deg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      HStack {
        Button(viewModel.isMonitoring ? "Stop" : "Start") {
          viewModel.toggleMonitoring()
        }
        .keyboardShortcut(.defaultAction)

        Button("Calibrate") {
          viewModel.calibrate()
        }
        .disabled(!viewModel.canCalibrate)
      }

      if !viewModel.notificationsEnabled {
        Button("Enable Notifications") {
          viewModel.requestNotifications()
        }
      }

      Divider()

      Text(viewModel.sessionSummary)
        .font(.caption)
        .foregroundStyle(.secondary)

      SettingsLink {
        Text("Settings…")
      }

      Button("Quit") {
        viewModel.stopMonitoring()
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(12)
    .frame(width: 260)
  }
}
