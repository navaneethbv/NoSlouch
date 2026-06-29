import SwiftUI

@main
struct NoSlouchApp: App {
  @StateObject private var viewModel = PostureViewModel()

  var body: some Scene {
    MenuBarExtra("NoSlouch", systemImage: "figure.stand") {
      MenuBarView(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(viewModel: viewModel)
    }
  }
}
