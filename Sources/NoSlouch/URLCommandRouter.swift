import Foundation

/// Commands accepted via the `noslouch://` URL scheme (E2) — the automation
/// surface for Shortcuts ("Open URL"), Raycast, or the shell
/// (`open "noslouch://snooze?minutes=30"`). Parsing is pure so it can be
/// unit-tested without launching the app; delivery is wired in
/// `NoSlouchApp` via `onOpenURL`.
public enum URLCommand: Equatable {
  case start
  case stop
  case calibrate
  case resume
  case snooze(minutes: Int)

  public static func parse(_ url: URL) -> URLCommand? {
    guard url.scheme?.lowercased() == "noslouch" else {
      return nil
    }
    switch (url.host ?? "").lowercased() {
    case "start":
      return .start
    case "stop":
      return .stop
    case "calibrate":
      return .calibrate
    case "resume":
      return .resume
    case "snooze":
      let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first { $0.name == "minutes" }?
        .value
      let minutes: Int
      if let raw {
        guard let parsed = Int(raw) else {
          return nil
        }
        minutes = parsed
      } else {
        minutes = 15
      }
      guard minutes > 0 else {
        return nil
      }
      return .snooze(minutes: minutes)
    default:
      return nil
    }
  }
}
