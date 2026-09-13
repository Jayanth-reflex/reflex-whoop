import Foundation

/// The last few minutes of live heart rate, for the Band tab's chart. Display
/// state only: every reading already reaches the database through the inbox.
struct HeartRateWindow: Equatable {
    let span: TimeInterval
    private(set) var readings: [HeartRateReading] = []

    init(span: TimeInterval) {
        self.span = span
    }

    mutating func append(bpm: Int, at time: Date) {
        readings.append(HeartRateReading(time: time, bpm: Double(bpm)))
        let cutoff = time.addingTimeInterval(-span)
        if let firstKept = readings.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            readings.removeFirst(firstKept)
        }
    }

    var bpmRange: ClosedRange<Double>? {
        guard let lowest = readings.map(\.bpm).min(), let highest = readings.map(\.bpm).max() else { return nil }
        return lowest...highest
    }
}
