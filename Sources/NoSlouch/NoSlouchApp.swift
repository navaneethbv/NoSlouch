import SwiftUI

@main
struct NoSlouchApp: App {
    var body: some Scene {
        MenuBarExtra("NoSlouch", systemImage: "figure.stand") {
            Text("NoSlouch")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
