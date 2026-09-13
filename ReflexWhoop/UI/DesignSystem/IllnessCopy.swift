import Foundation

/// How the app words an illness flag, shared by Today and Unusual days.
enum IllnessCopy {
    static let title = "Your body may be fighting something"
    static let context = "That pattern often shows up a day or two before feeling ill."
    static let caveat = "A pattern in your numbers, not a diagnosis."

    /// Names the signals that moved, as a sentence.
    static func whatMoved(_ signals: [Metric], locale: Locale = .current) -> String {
        guard !signals.isEmpty else { return "Several signals moved away from your normal together." }
        let names = signals.map { $0.label.lowercased() }.formatted(.list(type: .and).locale(locale))
        return "\(names.prefix(1).uppercased())\(names.dropFirst()) all moved away from your normal together."
    }
}
