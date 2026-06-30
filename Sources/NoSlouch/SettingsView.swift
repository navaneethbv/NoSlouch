import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: PostureViewModel

  var body: some View {
    Form {
      Section("Detection") {
        // A3: Sensitivity preset shortcuts
        HStack {
          Text("Preset")
          Spacer()
          ForEach(SensitivityPreset.allCases, id: \.self) { preset in
            Button(preset.rawValue) {
              viewModel.applyPreset(preset)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }

        Divider()

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
          "Auto-drift calibration",
          isOn: Binding(
            get: { viewModel.settings.autoDriftEnabled },
            set: { viewModel.updateAutoDriftEnabled($0) }
          )
        )
      }

      Section("Alerts") {
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
      }

      Section("Reminders") {
        // Break & stretch
        Toggle(
          "Break reminders",
          isOn: Binding(
            get: { viewModel.settings.breakRemindersEnabled },
            set: { viewModel.updateBreakRemindersEnabled($0) }
          )
        )
        if viewModel.settings.breakRemindersEnabled {
          Stepper(
            "Break interval: \(viewModel.settings.breakReminderMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.breakReminderMinutes },
              set: { viewModel.updateBreakReminderMinutes($0) }
            ),
            in: 10...120,
            step: 5
          )
        }

        Divider()

        // Eye rest (20-20-20)
        Toggle(
          "Eye rest (20-20-20)",
          isOn: Binding(
            get: { viewModel.settings.eyeRestEnabled },
            set: { viewModel.updateEyeRestEnabled($0) }
          )
        )
        if viewModel.settings.eyeRestEnabled {
          Stepper(
            "Eye rest interval: \(viewModel.settings.eyeRestMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.eyeRestMinutes },
              set: { viewModel.updateEyeRestMinutes($0) }
            ),
            in: 5...60,
            step: 5
          )
        }

        Divider()

        // Hydration
        Toggle(
          "Hydration reminders",
          isOn: Binding(
            get: { viewModel.settings.hydrationEnabled },
            set: { viewModel.updateHydrationEnabled($0) }
          )
        )
        if viewModel.settings.hydrationEnabled {
          Stepper(
            "Hydration interval: \(viewModel.settings.hydrationMinutes, specifier: "%.0f") min",
            value: Binding(
              get: { viewModel.settings.hydrationMinutes },
              set: { viewModel.updateHydrationMinutes($0) }
            ),
            in: 15...120,
            step: 15
          )
        }
      }

      Section("System") {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { viewModel.launchAtLogin },
            set: { viewModel.setLaunchAtLogin($0) }
          )
        )
      }
    }
    .frame(width: 340)
  }
}
