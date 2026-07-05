import AppKit
import Charts
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
  @ObservedObject var viewModel: PostureViewModel
  @State private var selectedDay: Date? = nil
  @State private var granularity: TrendGranularity = .day

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    return formatter
  }()

  private static let weekdayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE"
    return formatter
  }()

  private var recentStats: [DayPostureStat] {
    Array(viewModel.dailyStats.suffix(30))
  }

  /// Day view shows the recent 30 days; week/month roll up the full retained
  /// history so the coarser buckets aren't clipped mid-period.
  private var trendPoints: [TrendPoint] {
    let source = granularity == .day ? recentStats : viewModel.dailyStats
    return TrendAggregator.points(
      stats: source, granularity: granularity, calendar: .current)
  }

  private var trendUnit: Calendar.Component {
    switch granularity {
    case .day: return .day
    case .week: return .weekOfYear
    case .month: return .month
    }
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
        HStack {
          Text("Upright share by \(granularity.rawValue.lowercased())")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Picker("Granularity", selection: $granularity) {
            ForEach(TrendGranularity.allCases) { granularity in
              Text(granularity.rawValue).tag(granularity)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 180)
        }

        Chart(trendPoints) { point in
          BarMark(
            x: .value("Period", point.periodStart, unit: trendUnit),
            y: .value("Upright %", point.uprightPercent)
          )
          .foregroundStyle(.green)
          .cornerRadius(2)
        }
        .chartYScale(domain: 0...100)
        .frame(height: 110)

        Divider()

        heatmapSection

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
    .frame(width: 460, height: 660)
  }

  // MARK: - Hour × day heatmap (C1)

  /// The last 7 calendar days, oldest first, ending today.
  private var heatmapDays: [Date] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    return (0..<7).compactMap { offset in
      calendar.date(byAdding: .day, value: offset - 6, to: today)
    }
  }

  private var heatmapCells: [Date: HourPostureStat] {
    Dictionary(viewModel.hourlyStats.map { ($0.hour, $0) }, uniquingKeysWith: { first, _ in first })
  }

  @ViewBuilder private var heatmapSection: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Upright share by hour, last 7 days")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        // Sequential single-hue ramp: darker green = more upright. Exact values
        // are in each cell's tooltip so color is never the only channel.
        Text("light → dark = 0 → 100% upright")
          .font(.system(size: 8))
          .foregroundStyle(.tertiary)
      }

      let calendar = Calendar.current
      Grid(horizontalSpacing: 2, verticalSpacing: 2) {
        ForEach(heatmapDays, id: \.self) { day in
          GridRow {
            Text(Self.weekdayFormatter.string(from: day))
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
              .frame(width: 26, alignment: .leading)
            ForEach(0..<24, id: \.self) { hour in
              heatmapCell(day: day, hour: hour, calendar: calendar)
            }
          }
        }
        GridRow {
          Text("")
            .frame(width: 26)
          ForEach(0..<24, id: \.self) { hour in
            Text(hour % 6 == 0 ? "\(hour)" : "")
              .font(.system(size: 7))
              .foregroundStyle(.tertiary)
              .frame(maxWidth: .infinity)
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Hour by day posture heatmap; darker green means more upright time")
    }
  }

  @ViewBuilder
  private func heatmapCell(day: Date, hour: Int, calendar: Calendar) -> some View {
    let bucket = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    let stat = bucket.flatMap { heatmapCells[$0] }
    let measured = (stat?.goodSeconds ?? 0) + (stat?.badSeconds ?? 0)

    RoundedRectangle(cornerRadius: 2)
      .fill(cellColor(stat: stat, measured: measured))
      .frame(height: 12)
      .frame(maxWidth: .infinity)
      .help(cellHelp(day: day, hour: hour, stat: stat, measured: measured))
  }

  private func cellColor(stat: HourPostureStat?, measured: TimeInterval) -> Color {
    guard let stat, measured > 0 else {
      return Color.secondary.opacity(0.08)
    }
    let fraction = stat.goodSeconds / measured
    return Color.green.opacity(0.15 + 0.85 * fraction)
  }

  private func cellHelp(day: Date, hour: Int, stat: HourPostureStat?, measured: TimeInterval)
    -> String
  {
    let label = "\(Self.dayFormatter.string(from: day)), \(hour):00"
    guard let stat, measured > 0 else {
      return "\(label) — no data"
    }
    let percent = Int((stat.goodSeconds / measured * 100).rounded())
    let minutes = Int((measured / 60).rounded())
    return "\(label) — \(percent)% upright over \(minutes) min, \(stat.slouchEvents) slouches"
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
