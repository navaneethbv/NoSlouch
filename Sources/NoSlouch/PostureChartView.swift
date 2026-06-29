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
      LineMark(
        x: .value("t", sample.timestamp),
        y: .value("drop", sample.deviation)
      )

      RuleMark(y: .value("threshold", viewModel.settings.thresholdDegrees))
        .lineStyle(StrokeStyle(dash: [4]))
    }
    .frame(height: 80)
  }
}
