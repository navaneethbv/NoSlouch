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

      Stepper(
        "Threshold: \(viewModel.settings.thresholdDegrees, specifier: "%.0f") deg",
        value: Binding(
          get: { viewModel.settings.thresholdDegrees },
          set: { viewModel.updateThreshold($0) }
        ),
        in: 5...30,
        step: 1
      )

      Stepper(
        "Reminder: \(viewModel.settings.alertCooldownSeconds, specifier: "%.0f") sec",
        value: Binding(
          get: { viewModel.settings.alertCooldownSeconds },
          set: { viewModel.updateAlertCooldown($0) }
        ),
        in: 10...300,
        step: 10
      )

      Toggle(
        "Sound",
        isOn: Binding(
          get: { viewModel.settings.soundEnabled },
          set: { viewModel.updateSoundEnabled($0) }
        ))

      Toggle(
        "Invert pitch",
        isOn: Binding(
          get: { viewModel.settings.invertedPitch },
          set: { viewModel.updateInvertedPitch($0) }
        ))

      if !viewModel.notificationsEnabled {
        Button("Enable Notifications") {
          viewModel.requestNotifications()
        }
      }

      Divider()

      Text(viewModel.sessionSummary)
        .font(.caption)
        .foregroundStyle(.secondary)

      Button("Quit") {
        viewModel.stopMonitoring()
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(12)
    .frame(width: 260)
  }
}
