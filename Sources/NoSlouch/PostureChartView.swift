import Charts
import Foundation
import SwiftUI

struct DeviationSample: Identifiable, Equatable {
  var id: Date { timestamp }
  let timestamp: Date
  let deviation: Double
}

struct PostureChartView: View {
  @ObservedObject var viewModel: PostureViewModel

  var body: some View {
    Chart(viewModel.deviationSamples) { sample in
      AreaMark(
        x: .value("t", sample.timestamp),
        y: .value("drop", sample.deviation)
      )
      .foregroundStyle(
        LinearGradient(
          colors: [
            viewModel.postureState == .bad ? .red.opacity(0.25) : .green.opacity(0.25),
            viewModel.postureState == .bad ? .red.opacity(0.0) : .green.opacity(0.0),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )

      LineMark(
        x: .value("t", sample.timestamp),
        y: .value("drop", sample.deviation)
      )
      .foregroundStyle(viewModel.postureState == .bad ? .red : .green)

      RuleMark(y: .value("threshold", viewModel.settings.thresholdDegrees))
        .lineStyle(StrokeStyle(dash: [4]))
        .foregroundStyle(.red.opacity(0.6))
    }
    .frame(height: 80)
  }
}
