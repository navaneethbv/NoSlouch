import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: PostureViewModel
  @State private var profileName = ""
  @State private var snoozePresetsText = ""

  var body: some View {
    Form {
      Section("Detection") {
        // Hand-tuned values show as "Custom" instead of masquerading as
        // "Standard", which re-selecting would silently overwrite (NB-29).
        Picker(
          "Sensitivity",
          selection: Binding(
            get: { viewModel.currentPreset },
            set: { preset in
              if let preset {
                viewModel.applyPreset(preset)
              }
            }
          )
        ) {
          ForEach(DetectionPreset.allCases) { preset in
            Text(preset.displayName).tag(Optional(preset))
          }
          if viewModel.currentPreset == nil {
            Text("Custom").tag(Optional<DetectionPreset>.none)
          }
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
          "Hold: \(viewModel.settings.holdSeconds, specifier: "%.1f") sec",
          value: Binding(
            get: { viewModel.settings.holdSeconds },
            set: { viewModel.updateHoldSeconds($0) }
          ),
          in: 1...10,
          step: 0.5
        )

        Stepper(
          "Recover: \(viewModel.settings.recoverSeconds, specifier: "%.1f") sec",
          value: Binding(
            get: { viewModel.settings.recoverSeconds },
            set: { viewModel.updateRecoverSeconds($0) }
          ),
          in: 0.5...5,
          step: 0.5
        )

        Toggle(
          "Inverted pitch",
          isOn: Binding(
            get: { viewModel.settings.invertedPitch },
            set: { viewModel.updateInvertedPitch($0) }
          )
        )

        Toggle(
          "Auto-adjust baseline (drift)",
          isOn: Binding(
            get: { viewModel.settings.autoDriftEnabled },
            set: { viewModel.updateAutoDriftEnabled($0) }
          )
        )

        Toggle(
          "Detect head tilt",
          isOn: Binding(
            get: { viewModel.settings.tiltDetectionEnabled },
            set: { viewModel.updateTiltDetectionEnabled($0) }
          )
        )
        if viewModel.settings.tiltDetectionEnabled {
          Stepper(
            "Tilt threshold: \(viewModel.settings.tiltThresholdDegrees, specifier: "%.0f") deg",
            value: Binding(
              get: { viewModel.settings.tiltThresholdDegrees },
              set: { viewModel.updateTiltThreshold($0) }
            ),
            in: 5...45,
            step: 1
          )
        }

        Stepper(
          "Recalibrate reminder: \(viewModel.settings.recalibrationReminderDays, specifier: "%.0f") days",
          value: Binding(
            get: { viewModel.settings.recalibrationReminderDays },
            set: { viewModel.updateRecalibrationReminderDays($0) }
          ),
          in: 1...90,
          step: 1
        )
      }

      Section("Calibration") {
        Button("Guide Me Through Calibration") { viewModel.beginGuidedCalibration() }
          .disabled(viewModel.isCalibrating)
        Text(viewModel.calibrationMessage).font(.caption)
        if viewModel.isCalibrating {
          Button("Cancel Calibration") { viewModel.cancelCalibration() }
        }
        TextField("Profile name (for example, Sitting)", text: $profileName)
        Button("Save Current Calibration") {
          viewModel.saveCalibrationProfile(named: profileName)
          profileName = ""
        }
        .disabled(
          profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || profileName.count > 40 || viewModel.settings.calibratedBaselinePitch == nil)
        ForEach(viewModel.calibrationProfiles) { profile in
          HStack {
            Button("Use \(profile.name)") { viewModel.applyCalibrationProfile(profile) }
            Spacer()
            Button("Delete \(profile.name)", role: .destructive) {
              viewModel.deleteCalibrationProfile(profile)
            }
          }
        }
      }

      Section("Goals") {
        Stepper(
          "Minimum measured time: \(Int(viewModel.settings.minimumDailyMinutes)) min",
          value: Binding(
            get: { viewModel.settings.minimumDailyMinutes },
            set: { viewModel.updateMinimumDailyMinutes($0) }), in: 1...240, step: 5)
        Text("Daily grades, goals, and day achievements require this much measured posture time.")
          .font(.caption)
        Stepper(
          "Daily upright goal: \(viewModel.settings.dailyUprightGoalPercent, specifier: "%.0f")%",
          value: Binding(
            get: { viewModel.settings.dailyUprightGoalPercent },
            set: { viewModel.updateDailyUprightGoal($0) }
          ),
          in: 50...100,
          step: 5
        )

        Toggle(
          "Weekly digest",
          isOn: Binding(
            get: { viewModel.settings.weeklyDigestEnabled },
            set: { viewModel.updateWeeklyDigestEnabled($0) }
          )
        )
      }

      Section("Alerts") {
        Button(viewModel.isTestingNotification ? "Sending Test..." : "Send Test Notification") {
          viewModel.sendTestNotification()
        }
        .disabled(viewModel.isTestingNotification)
        Text("Sends one test now using your sound and speech settings, even during quiet hours.")
          .font(.caption)
        if let message = viewModel.testNotificationMessage {
          Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        if !viewModel.notificationsEnabled {
          Button("Enable Notifications") { viewModel.requestNotifications() }
        }
        Button("Open Notification Settings") { viewModel.openNotificationSettings() }

        Stepper(
          "Cooldown: \(viewModel.settings.alertCooldownSeconds, specifier: "%.0f") sec",
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
          )
        )

        Picker(
          "Sound name",
          selection: Binding(
            get: { viewModel.settings.soundName },
            set: { viewModel.updateSoundName($0) }
          )
        ) {
          ForEach(AppSettings.availableSoundNames, id: \.self) { name in
            Text(name).tag(name)
          }
        }

        Button("Preview") {
          viewModel.previewSound()
        }

        Toggle(
          "Speech",
          isOn: Binding(
            get: { viewModel.settings.speechEnabled },
            set: { viewModel.updateSpeechEnabled($0) }
          )
        )

        Toggle(
          "Mute in meetings",
          isOn: Binding(
            get: { viewModel.settings.muteInMeetings },
            set: { viewModel.updateMuteInMeetings($0) }
          )
        )

        Toggle(
          "Escalate repeated nudges",
          isOn: Binding(
            get: { viewModel.settings.escalatingNudges },
            set: { viewModel.updateEscalatingNudges($0) }
          )
        )

        TextField(
          "Custom messages (one per line)",
          text: Binding(
            get: { viewModel.settings.customNudgeMessages.joined(separator: "\n") },
            set: { newValue in
              let lines = newValue.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
              viewModel.updateCustomNudgeMessages(lines)
            }
          ),
          axis: .vertical
        )
        .lineLimit(3, reservesSpace: true)

        Toggle(
          "Low AirPods battery warning",
          isOn: Binding(
            get: { viewModel.settings.lowBatteryWarningEnabled },
            set: { viewModel.updateLowBatteryWarningEnabled($0) }
          )
        )

        // Local state, committed on submit/focus loss: parsing per keystroke
        // strips the separator the user just typed, making "15, 30" untypable
        // (NB-20).
        TextField(
          "Snooze options (min, comma-separated)",
          text: $snoozePresetsText
        )
        .onAppear {
          snoozePresetsText = Self.snoozeText(viewModel.settings.snoozePresetsMinutes)
        }
        .onSubmit(commitSnoozePresets)
      }

      Section("Reminders") {
        Toggle(
          "Stretch break",
          isOn: Binding(
            get: { viewModel.settings.breakRemindersEnabled },
            set: { viewModel.updateBreakRemindersEnabled($0) }
          )
        )
        if viewModel.settings.breakRemindersEnabled {
          Stepper(
            "Break every \(viewModel.settings.breakReminderMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.breakReminderMinutes },
              set: { viewModel.updateBreakReminderMinutes($0) }
            ),
            in: 10...120,
            step: 5
          )
        }

        Toggle(
          "Eye rest (20-20-20)",
          isOn: Binding(
            get: { viewModel.settings.eyeRestEnabled },
            set: { viewModel.updateEyeRestEnabled($0) }
          )
        )
        if viewModel.settings.eyeRestEnabled {
          Stepper(
            "Eyes every \(viewModel.settings.eyeRestMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.eyeRestMinutes },
              set: { viewModel.updateEyeRestMinutes($0) }
            ),
            in: 5...60,
            step: 5
          )
        }

        Toggle(
          "Hydration",
          isOn: Binding(
            get: { viewModel.settings.hydrationEnabled },
            set: { viewModel.updateHydrationEnabled($0) }
          )
        )
        if viewModel.settings.hydrationEnabled {
          Stepper(
            "Water every \(viewModel.settings.hydrationMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.hydrationMinutes },
              set: { viewModel.updateHydrationMinutes($0) }
            ),
            in: 15...120,
            step: 5
          )
        }

        Toggle(
          "Movement",
          isOn: Binding(
            get: { viewModel.settings.movementRemindersEnabled },
            set: { viewModel.updateMovementRemindersEnabled($0) }
          )
        )
        if viewModel.settings.movementRemindersEnabled {
          Stepper(
            "Move every \(viewModel.settings.movementMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.movementMinutes },
              set: { viewModel.updateMovementMinutes($0) }
            ),
            in: 15...120,
            step: 5
          )
        }
      }

      Section("Quiet Hours") {
        Toggle(
          "Silence alerts during quiet hours",
          isOn: Binding(
            get: { viewModel.settings.quietHoursEnabled },
            set: { viewModel.updateQuietHoursEnabled($0) }
          )
        )
        if viewModel.settings.quietHoursEnabled {
          Stepper(
            "From \(Self.timeLabel(viewModel.settings.quietStartMinutes))",
            value: Binding(
              get: { viewModel.settings.quietStartMinutes },
              set: { viewModel.updateQuietStartMinutes($0) }
            ),
            in: 0...1_410,
            step: 30
          )
          Stepper(
            "Until \(Self.timeLabel(viewModel.settings.quietEndMinutes))",
            value: Binding(
              get: { viewModel.settings.quietEndMinutes },
              set: { viewModel.updateQuietEndMinutes($0) }
            ),
            in: 0...1_410,
            step: 30
          )
        }
      }

      Section("System") {
        Toggle(
          "Start monitoring when NoSlouch opens",
          isOn: Binding(
            get: { viewModel.settings.startMonitoringAtLaunch },
            set: { viewModel.updateStartMonitoringAtLaunch($0) }))
        Text(
          "After setup, waits for supported headphones at launch. Stop cancels automatic tracking for this launch."
        )
        .font(.caption)

        Toggle(
          "Resume after reconnect or wake",
          isOn: Binding(
            get: { viewModel.settings.resumeAfterInterruption },
            set: { viewModel.updateResumeAfterInterruption($0) }))
        Text("Resumes interrupted monitoring. Pressing Stop always cancels automatic resume.").font(
          .caption)
        Button("Open Motion Settings") { viewModel.openMotionSettings() }
        Text(viewModel.diagnosticsText).font(.caption)
        if let error = viewModel.systemError { Text(error).foregroundStyle(.red) }

        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.setLaunchAtLogin($0) }
          )
        )

        Toggle(
          "Pause when away from desk",
          isOn: Binding(
            get: { viewModel.settings.pauseWhenAwayEnabled },
            set: { viewModel.updatePauseWhenAwayEnabled($0) }
          )
        )
      }
    }
    .onAppear { viewModel.refreshNotificationAuthorization() }
    .formStyle(.grouped)
    .frame(width: 480, height: 640)
  }

  private func commitSnoozePresets() {
    var seen = Set<Int>()
    let values = snoozePresetsText.split(separator: ",")
      .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
      .filter { $0 > 0 && seen.insert($0).inserted }
    let resolved = values.isEmpty ? [15, 30, 60] : values
    viewModel.updateSnoozePresets(resolved)
    snoozePresetsText = Self.snoozeText(resolved)
  }

  private static func snoozeText(_ minutes: [Int]) -> String {
    minutes.map(String.init).joined(separator: ", ")
  }

  private static func timeLabel(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }
}
