import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var viewModel: PostureViewModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("NoSlouch")
          .font(.headline)
        Spacer()
        if viewModel.isMicActive && viewModel.settings.muteInMeetings {
          Image(systemName: "mic.slash.fill")
            .foregroundStyle(.red)
            .font(.caption)
        }
      }

      Text(viewModel.statusText)
        .font(.callout)
        .bold()
        .foregroundStyle(
          viewModel.postureState == .bad
            ? .red
            : (viewModel.isMicActive && viewModel.settings.muteInMeetings ? .orange : .secondary))

      if viewModel.isMonitoring, let calibratedPitch = viewModel.lastCalibratedPitch,
        let pitch = viewModel.currentPitch
      {
        let threshold = viewModel.settings.thresholdDegrees
        let drop =
          viewModel.settings.invertedPitch
          ? pitch - calibratedPitch
          : calibratedPitch - pitch

        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text("Posture Deviation")
              .font(.system(size: 10))
              .bold()
              .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f°", drop))
              .font(.system(size: 10))
              .bold()
              .foregroundStyle(viewModel.postureState == .bad ? .red : .green)
          }

          GeometryReader { geo in
            ZStack(alignment: .leading) {
              RoundedRectangle(cornerRadius: 3)
                .fill(.secondary.opacity(0.15))
                .frame(height: 6)

              // Threshold marker
              Rectangle()
                .fill(.red.opacity(0.6))
                .frame(width: 2, height: 10)
                .offset(x: geo.size.width * CGFloat(min(1.0, max(0.0, threshold / 30.0))))

              // Progress bar
              let progress = min(1.0, max(0.0, drop / 30.0))
              RoundedRectangle(cornerRadius: 3)
                .fill(viewModel.postureState == .bad ? .red : .green)
                .frame(width: geo.size.width * CGFloat(progress), height: 6)
            }
          }
          .frame(height: 10)

          HStack {
            Text("Baseline")
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
            Spacer()
            Text("Limit (\(Int(threshold))°)")
              .font(.system(size: 8))
              .foregroundStyle(.red.opacity(0.8))
            Spacer()
            Text("Max (30°)")
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 4)
      } else {
        VStack(alignment: .leading, spacing: 2) {
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
        }
      }

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

      if viewModel.isMonitoring {
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
              Text("UPRIGHT")
                .font(.system(size: 8))
                .bold()
                .foregroundStyle(.green)
              Text(formattedSeconds(viewModel.sessionGoodSeconds))
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.green.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
              Text("SLOUCHES")
                .font(.system(size: 8))
                .bold()
                .foregroundStyle(.red)
              Text("\(viewModel.sessionSlouchEvents)")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.08)))
          }

          HStack(spacing: 8) {
            let today = Calendar.current.startOfDay(for: Date())
            let stored = viewModel.dailyStats.first {
              Calendar.current.isDate($0.day, inSameDayAs: today)
            }
            let good = (stored?.goodSeconds ?? 0) + viewModel.sessionGoodSeconds
            let bad = (stored?.badSeconds ?? 0) + viewModel.sessionBadSeconds
            let measured = good + bad
            let percent = measured > 0 ? Int((good / measured * 100).rounded()) : 0

            VStack(alignment: .leading, spacing: 2) {
              Text("TODAY UPRIGHT")
                .font(.system(size: 8))
                .bold()
                .foregroundStyle(.blue)
              Text("\(percent)%")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
              Text("SESSIONS")
                .font(.system(size: 8))
                .bold()
                .foregroundStyle(.orange)
              let sessionCount = (stored?.sessionCount ?? 0) + (viewModel.isMonitoring ? 1 : 0)
              Text("\(sessionCount)")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.08)))
          }
        }

        PostureChartView(viewModel: viewModel)
      } else {
        HStack(spacing: 8) {
          let today = Calendar.current.startOfDay(for: Date())
          let stored = viewModel.dailyStats.first {
            Calendar.current.isDate($0.day, inSameDayAs: today)
          }
          let good = (stored?.goodSeconds ?? 0)
          let bad = (stored?.badSeconds ?? 0)
          let measured = good + bad
          let percent = measured > 0 ? Int((good / measured * 100).rounded()) : 0

          VStack(alignment: .leading, spacing: 2) {
            Text("TODAY UPRIGHT")
              .font(.system(size: 8))
              .bold()
              .foregroundStyle(.blue)
            Text("\(percent)%")
              .font(.title3)
              .bold()
              .foregroundStyle(.primary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(RoundedRectangle(cornerRadius: 6).fill(.blue.opacity(0.05)))

          VStack(alignment: .leading, spacing: 2) {
            Text("SESSIONS TODAY")
              .font(.system(size: 8))
              .bold()
              .foregroundStyle(.orange)
            Text("\(stored?.sessionCount ?? 0)")
              .font(.title3)
              .bold()
              .foregroundStyle(.primary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.05)))
        }
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
    .onAppear {
      viewModel.refreshNotificationAuthorization()
    }
  }

  private func formattedSeconds(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
