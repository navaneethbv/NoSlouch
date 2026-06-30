import Charts
import Foundation
import SwiftUI

struct HistoryView: View {
  @ObservedObject var viewModel: PostureViewModel

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    return formatter
  }()

  private var recentStats: [DayPostureStat] {
    Array(viewModel.dailyStats.suffix(30))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Posture History")
        .font(.title2)
        .bold()

      if recentStats.isEmpty {
        Text("No sessions recorded yet. Start monitoring to build your history.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text("Upright share, last \(recentStats.count) day(s)")
          .font(.caption)
          .foregroundStyle(.secondary)

        Chart(recentStats) { stat in
          BarMark(
            x: .value("Day", stat.day, unit: .day),
            y: .value("Upright %", stat.uprightFraction * 100)
          )
          .foregroundStyle(.green)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 140)

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(recentStats.reversed()) { stat in
              HStack {
                Text(Self.dayFormatter.string(from: stat.day))
                  .frame(width: 110, alignment: .leading)
                Text("\(Int((stat.uprightFraction * 100).rounded()))% upright")
                  .frame(width: 90, alignment: .leading)
                Text(formattedMinutes(stat.totalSeconds))
                  .frame(width: 70, alignment: .leading)
                Text("\(stat.slouchEvents) slouches")
                  .foregroundStyle(.secondary)
              }
              .font(.callout)
            }
          }
        }
      }
    }
    .padding(16)
    .frame(width: 420, height: 360)
  }

  private func formattedMinutes(_ seconds: TimeInterval) -> String {
    let minutes = Int((max(0, seconds) / 60).rounded())
    return "\(minutes) min"
  }
}
