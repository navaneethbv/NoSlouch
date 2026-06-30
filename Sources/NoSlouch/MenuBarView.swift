import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var viewModel: PostureViewModel
  @Environment(\.openWindow) private var openWindow

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

      if viewModel.isMonitoring {
        if viewModel.snoozedUntil == nil {
          Menu("Snooze nudges") {
            Button("15 minutes") { viewModel.snoozeNudges(for: 15 * 60) }
            Button("30 minutes") { viewModel.snoozeNudges(for: 30 * 60) }
            Button("60 minutes") { viewModel.snoozeNudges(for: 60 * 60) }
          }
        } else {
          Button("Resume nudges") {
            viewModel.resumeNudges()
          }
        }
      }

      Divider()

      Text(viewModel.sessionSummary)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(viewModel.todayUprightText)
        .font(.caption)
        .foregroundStyle(.secondary)

      if viewModel.isMonitoring {
        HStack {
          Text("Upright \(formattedSeconds(viewModel.sessionGoodSeconds))")
          Text("·")
          Text("Slouches \(viewModel.sessionSlouchEvents)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)

        PostureChartView(viewModel: viewModel)
      }

      Button("History…") {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "history")
      }

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

  private func formattedSeconds(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
