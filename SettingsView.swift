import SwiftUI

struct SettingsView: View {
  @ObservedObject var viewModel: PostureViewModel

  var body: some View {
    Form {
      Section("Detection") {
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
