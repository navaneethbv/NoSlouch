import SwiftUI

@main
struct NoSlouchApp: App {
  @StateObject private var viewModel = PostureViewModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(viewModel: viewModel)
    } label: {
      Image(systemName: viewModel.menuBarSymbolName)
    }
    .menuBarExtraStyle(.window)

    Window("Posture History", id: "history") {
      HistoryView(viewModel: viewModel)
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView(viewModel: viewModel)
    }
  }
}
