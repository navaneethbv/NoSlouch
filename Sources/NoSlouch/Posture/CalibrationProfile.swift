import Foundation

struct CalibrationProfile: Codable, Equatable, Identifiable {
  var id: String { name }
  let name: String
  let pitch: Double
  let roll: Double
  let savedAt: Date

  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && name.count <= 40 && pitch.isFinite && roll.isFinite
      && abs(pitch) <= 180 && abs(roll) <= 180
      && savedAt.timeIntervalSinceReferenceDate.isFinite
  }
}
