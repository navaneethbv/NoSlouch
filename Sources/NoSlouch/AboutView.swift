import SwiftUI

/// The About window (F3): name, tagline, version from the bundle, and the
/// automation cheat-sheet for the `noslouch://` scheme.
struct AboutView: View {
  private var versionText: String {
    let short =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
  }

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "figure.stand")
        .font(.system(size: 42))
        .foregroundStyle(.green)
      Text("NoSlouch")
        .font(.title2)
        .bold()
      Text("Posture & desk-wellness companion for Mac")
        .font(.callout)
        .foregroundStyle(.secondary)
      Text(versionText)
        .font(.caption)
        .foregroundStyle(.secondary)

      Divider()
        .padding(.horizontal, 24)

      VStack(alignment: .leading, spacing: 2) {
        Text("Automation (Shortcuts → Open URL):")
          .font(.caption)
          .bold()
        Text("noslouch://start · noslouch://stop · noslouch://calibrate")
        Text("noslouch://snooze?minutes=30 · noslouch://resume")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      Text("Your posture data never leaves this Mac.")
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
    }
    .padding(24)
    .frame(width: 380, height: 300)
  }
}
