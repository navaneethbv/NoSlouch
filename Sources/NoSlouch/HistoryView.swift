import Charts
import Foundation
import SwiftUI

struct HistoryView: View {
  @ObservedObject var viewModel: PostureViewModel
  @State private var selectedDay: Date? = nil

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    return formatter
  }()

  private var recentStats: [DayPostureStat] {
    Array(viewModel.dailyStats.suffix(30))
  }

  private var activeSelectedDay: Date? {
    selectedDay ?? recentStats.last?.day
  }

  private var hourlyStatsForSelectedDay: [HourPostureStat] {
    guard let activeSelectedDay else { return [] }
    let calendar = Calendar.current
    return viewModel.hourlyStats.filter { calendar.isDate($0.hour, inSameDayAs: activeSelectedDay) }
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
        .frame(height: 110)

        Divider()

        if let activeSelectedDay {
          Text("Hourly slouch events on \(Self.dayFormatter.string(from: activeSelectedDay))")
            .font(.caption)
            .foregroundStyle(.secondary)

          let hourlyData = hourlyStatsForSelectedDay
          if hourlyData.isEmpty {
            Text("No intraday stats recorded for this day.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(height: 90)
              .frame(maxWidth: .infinity, alignment: .center)
          } else {
            Chart(hourlyData) { stat in
              BarMark(
                x: .value("Hour", stat.hour, unit: .hour),
                y: .value("Slouches", stat.slouchEvents)
              )
              .foregroundStyle(.orange)
            }
            .frame(height: 90)
            .chartXAxis {
              AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
              }
            }
          }
        }

        Divider()

        ScrollView {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(recentStats.reversed()) { stat in
              Button(action: { selectedDay = stat.day }) {
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
                .contentShape(Rectangle())
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
              }
              .buttonStyle(.plain)
              .background(
                activeSelectedDay == stat.day ? Color.accentColor.opacity(0.15) : Color.clear
              )
              .cornerRadius(6)
            }
          }
        }
      }
    }
    .padding(16)
    .frame(width: 460, height: 520)
  }

  private func formattedMinutes(_ seconds: TimeInterval) -> String {
    let minutes = Int((max(0, seconds) / 60).rounded())
    return "\(minutes) min"
  }
}
