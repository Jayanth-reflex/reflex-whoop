import SwiftUI

/// What VoiceOver's Audio Graph and chart detail read for a metric's history:
/// each day's value, and which days were unusual.
struct MetricHistoryChartDescriptor: AXChartDescriptorRepresentable {
    /// Already in the unit they're shown in (`MetricPoint.displayed`).
    let points: [MetricPoint]
    let metric: Metric
    let temperature: TemperatureUnit

    func makeChartDescriptor() -> AXChartDescriptor {
        let times = points.map { $0.date.timeIntervalSince1970 }
        let values = points.map(\.value)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Day",
            range: (times.min() ?? 0)...(times.max() ?? 0),
            gridlinePositions: []
        ) { Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted) }
        let yAxis = AXNumericDataAxisDescriptor(
            title: metric.label,
            range: (values.min() ?? 0)...(values.max() ?? 0),
            gridlinePositions: []
        ) { metric.formatted(displayValue: $0) + metric.unitSuffix(temperature) }
        let series = AXDataSeriesDescriptor(
            name: metric.label,
            isContinuous: false,
            dataPoints: points.map { point in
                AXDataPoint(
                    x: point.date.timeIntervalSince1970,
                    y: point.value,
                    label: point.status.isUnusual ? point.status.label : nil
                )
            }
        )
        return AXChartDescriptor(
            title: metric.label,
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
