import SwiftUI

@main
struct NoSlouchApp: App {
  @StateObject private var viewModel = PostureViewModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarView(viewModel: viewModel)
    } label: {
      MenuBarLabel(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)

    Window("Posture History", id: "history") {
      HistoryView(viewModel: viewModel)
    }
    .windowResizability(.contentSize)

    Window("Welcome to NoSlouch", id: "onboarding") {
      OnboardingView(viewModel: viewModel)
    }
    .windowResizability(.contentSize)

    Window("About NoSlouch", id: "about") {
      AboutView()
    }
    .windowResizability(.contentSize)

    Settings {
      SettingsView(viewModel: viewModel)
    }
  }
}

/// The menu-bar icon. Unlike the popover content, the label is instantiated at
/// launch, so it is also where first-run onboarding gets presented — the app is
/// LSUIElement, and without this a new user only ever sees an unexplained
/// menu-bar glyph (NB-17).
private struct MenuBarLabel: View {
  @ObservedObject var viewModel: PostureViewModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(systemName: viewModel.menuBarSymbolName)
      .onAppear {
        guard viewModel.needsOnboarding else {
          return
        }
        DispatchQueue.main.async {
          NSApplication.shared.activate(ignoringOtherApps: true)
          openWindow(id: "onboarding")
        }
      }
      // noslouch:// automation commands (E2). The label is the one view alive
      // at launch in this LSUIElement app, so it hosts URL delivery too.
      .onOpenURL { url in
        guard let command = URLCommand.parse(url) else {
          return
        }
        viewModel.handle(command)
      }
  }
}
