import AppKit
import Charts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
      HStack {
        Text("Posture History")
          .font(.title2)
          .bold()
        Spacer()
        Button("Export CSV…") { exportCSV() }
      }

      Text(
        "🔥 \(viewModel.currentStreak)-day streak · best \(viewModel.longestStreak) · "
          + "goal \(Int(viewModel.settings.dailyUprightGoalPercent))%"
      )
      .font(.caption)
      .foregroundStyle(viewModel.goalMetToday ? .green : .secondary)

      if viewModel.settings.weeklyDigestEnabled {
        Text(viewModel.weeklyDigestText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 8) {
        if let grade = viewModel.todayGrade {
          Text("Today's grade: \(grade.rawValue)")
            .font(.caption)
            .bold()
        }
        ForEach(viewModel.unlockedAchievements) { achievement in
          Text(achievement.title)
            .font(.system(size: 9))
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(.yellow.opacity(0.2)))
            .help(achievement.detail)
        }
      }

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

  private func exportCSV() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "NoSlouch-history.csv"
    panel.allowedContentTypes = [.commaSeparatedText]
    guard panel.runModal() == .OK, let url = panel.url else {
      return
    }
    do {
      try viewModel.exportHistoryCSV().write(to: url, atomically: true, encoding: .utf8)
    } catch {
      NSSound.beep()
    }
  }
}
