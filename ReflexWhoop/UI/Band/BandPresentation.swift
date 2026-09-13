import Foundation

/// What the Band tab shows, from the recorder's connection state.
enum BandPresentation: Equatable {
    /// Not recording.
    case idle
    /// Connected and hearing from the band.
    case live
    /// Recording, but the band isn't connected right now.
    case searching
    case bluetoothOff
    case bluetoothDenied
    case unsupported

    /// `connection` is `nil` when nothing is recording.
    init(connection: BandConnection.ConnectionState?) {
        guard let connection else {
            self = .idle
            return
        }
        self = switch connection {
        case .ready: .live
        case .idle, .scanning, .connecting, .discoveringServices, .subscribing, .disconnected: .searching
        case .unavailable(.poweredOff): .bluetoothOff
        case .unavailable(.unauthorized): .bluetoothDenied
        case .unavailable(.unsupported): .unsupported
        }
    }
}
