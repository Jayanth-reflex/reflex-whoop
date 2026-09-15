import CoreBluetooth
import Foundation
import Observation

/// Direct CoreBluetooth connection to the band's `fd4b…` service. Owns the
/// central/peripheral delegate plumbing only — it has no idea what the bytes
/// mean and does not touch the database. Callers (see `SpikeRecorder`) get raw
/// frames via `onRawFrame` and decide what to do with them.
///
/// Runs entirely on the main queue (`CBCentralManager(delegate:queue: nil)`
/// defaults to it) — data volumes at this stage (HELLO/battery responses,
/// events, and whatever realtime stream the spike enables) are nowhere near
/// enough to need a dedicated queue, and `@Observable` state needs to be
/// touched from the main actor for SwiftUI anyway.
@Observable
@MainActor
final class BandConnection: NSObject {
    /// Why Core Bluetooth can't be used. A case rather than a message, so the
    /// UI can offer the right fix for each.
    enum Unavailability: Equatable {
        case poweredOff, unauthorized, unsupported
    }

    enum ConnectionState: Equatable {
        case idle
        case unavailable(Unavailability)
        case scanning
        case connecting
        case discoveringServices
        case subscribing
        case ready
        case disconnected(String)
    }

    private(set) var state: ConnectionState = .idle
    private(set) var peripheralName: String?

    /// Called for every raw notification, exactly as received, before any
    /// reassembly or decode attempt — this is what `SpikeRecorder` writes to
    /// `ingest_inbox`. `characteristic` identifies which of the four notify
    /// characteristics it arrived on.
    var onRawFrame: ((_ characteristic: CBUUID, _ data: Data, _ receivedAt: Date) -> Void)?

    /// Fired every time the connection reaches `.ready` — including after a
    /// reconnect or a state restoration, not just the first time. The band does
    /// not remember that we asked it to stream across a disconnect, so whatever
    /// enables streaming has to run again on each new connection.
    var onReady: (() -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var sequenceCounter: UInt8 = 0
    private var pendingWrite: CheckedContinuation<Void, Error>?

    /// When true, a dropped connection is immediately re-requested rather than
    /// left disconnected. `connect` with no timeout is the documented way to
    /// say "reconnect whenever this peripheral is reachable again" — iOS holds
    /// the request pending indefinitely, including while the app is suspended,
    /// and wakes us when the band comes back. This is what makes collection
    /// survive walking out of range, charging the band, or the app being
    /// backgrounded for hours.
    var autoReconnect = false

    /// Opting into Core Bluetooth state restoration. With this set (plus the
    /// `bluetooth-central` background mode), iOS can relaunch the app into the
    /// background after it has been terminated and hand the still-connected
    /// peripheral back via `willRestoreState`. Without it, termination ends
    /// collection until the user next opens the app by hand.
    ///
    /// The identifier must be stable across launches — it is how iOS matches a
    /// restored session to this manager.
    private static let restoreIdentifier = "com.reflexwhoop.band.central"

    /// `restoreState` must be false for a plain foreground spike (the Live
    /// screen) — a restorable manager asks iOS to relaunch us for BLE events,
    /// which is only wanted when continuous collection is actually enabled.
    func start(restoreState: Bool = false) {
        guard central == nil else { return }
        let options: [String: Any] = restoreState
            ? [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            : [:]
        central = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    func disconnect() {
        // Explicit user intent: stop trying to come back.
        autoReconnect = false
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        state = .idle
    }

    /// Builds and sends one command frame, and waits for the peripheral's
    /// write-completion callback before returning. `OpcodeAllowlist.
    /// assertAllowed` is called first and unconditionally — this is the only
    /// place in the codebase that writes to `writeCharacteristicUUID`, so this
    /// one check guards every outgoing command the app can ever send.
    ///
    /// Serialized on purpose: firing several `writeValue(type: .withResponse)`
    /// calls back-to-back with no wait between them lost two real commands in
    /// a live session (see docs/PROTOCOL-GEN5.md, "session 3") — CoreBluetooth
    /// silently dropped the earliest writes rather than queuing them. Waiting
    /// for each write's own completion (or a 3-second timeout, so one dead
    /// write can't wedge every command after it) avoids that.
    func send(opcode: Ble.AllowedOpcode, body: Data = Data()) async throws {
        try OpcodeAllowlist.assertAllowed(opcode.rawValue)
        guard let peripheral, let writeCharacteristic else {
            throw BandConnectionError.notReady
        }
        guard pendingWrite == nil else {
            throw BandConnectionError.writeInProgress
        }

        sequenceCounter &+= 1
        var inner = Data([Ble.PacketType.command.rawValue, sequenceCounter, opcode.rawValue])
        inner.append(body)
        // field = 1 is the only value confirmed on the wire so far (every one
        // of 711 captured frames in the discovery spike carried it) — see
        // docs/PROTOCOL-GEN5.md.
        let frame = Gen5Envelope.encode(field: 1, inner: inner)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingWrite = continuation
            // Gen 5 requires write-with-response — write-without-response is a
            // documented no-op (docs/PROTOCOL-GEN5.md's "Connection" table).
            peripheral.writeValue(frame, for: writeCharacteristic, type: .withResponse)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                // Only one write is ever in flight (guarded above), so if
                // `pendingWrite` is still set after the timeout it must still
                // be this one.
                if let pending = pendingWrite {
                    pendingWrite = nil
                    pending.resume(throwing: BandConnectionError.writeTimedOut)
                }
            }
        }
    }

    enum BandConnectionError: Error {
        case notReady
        case writeInProgress
        case writeTimedOut
    }

    private func beginConnecting() {
        guard let central else { return }
        if let already = central.retrieveConnectedPeripherals(withServices: [Ble.serviceUUID]).first {
            connect(to: already)
            return
        }
        state = .scanning
        central.scanForPeripherals(withServices: [Ble.serviceUUID])
    }

    private func connect(to peripheral: CBPeripheral) {
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        peripheralName = peripheral.name
        state = .connecting
        central?.connect(peripheral)
    }
}

extension BandConnection: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                beginConnecting()
            case .poweredOff:
                state = .unavailable(.poweredOff)
            case .unauthorized:
                state = .unavailable(.unauthorized)
            case .unsupported:
                state = .unavailable(.unsupported)
            case .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            connect(to: peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            state = .discoveringServices
            peripheral.discoverServices([Ble.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            state = .disconnected(error?.localizedDescription ?? "connect failed")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            state = .disconnected(error?.localizedDescription ?? "disconnected")
            writeCharacteristic = nil
            pendingWrite?.resume(throwing: BandConnectionError.notReady)
            pendingWrite = nil

            if autoReconnect {
                // Keep the peripheral reference: this request stays pending
                // until the band is reachable again, however long that takes.
                central.connect(peripheral)
                state = .connecting
            } else {
                self.peripheral = nil
            }
        }
    }

    /// Called when iOS relaunches the app to continue Bluetooth work it was
    /// doing before termination. Re-adopting the peripheral here is what lets a
    /// session resume without the user opening the app.
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        Task { @MainActor in
            self.central = central
            guard let peripheral = restored.first else { return }
            self.peripheral = peripheral
            peripheral.delegate = self
            peripheralName = peripheral.name
            autoReconnect = true

            if peripheral.state == .connected {
                // Still connected across the relaunch — re-discover so the
                // characteristic references (which did not survive) are valid.
                state = .discoveringServices
                peripheral.discoverServices([Ble.serviceUUID])
            } else {
                state = .connecting
                central.connect(peripheral)
            }
        }
    }
}

extension BandConnection: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Ble.serviceUUID }) else {
            Task { @MainActor in state = .disconnected(error?.localizedDescription ?? "service not found") }
            return
        }
        let chars = Ble.notifyCharacteristicUUIDs + [Ble.writeCharacteristicUUID]
        peripheral.discoverCharacteristics(chars, for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            Task { @MainActor in state = .disconnected(error?.localizedDescription ?? "characteristic discovery failed") }
            return
        }
        var foundWrite: CBCharacteristic?
        for characteristic in characteristics {
            if characteristic.uuid == Ble.writeCharacteristicUUID {
                foundWrite = characteristic
            } else if Ble.notifyCharacteristicUUIDs.contains(characteristic.uuid) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        Task { @MainActor in
            state = .subscribing
            writeCharacteristic = foundWrite
            // Optimistic: setNotifyValue calls above are fire-and-forget rather
            // than gated on didUpdateNotificationStateFor per characteristic —
            // fine for the spike (real correctness is CRC-checked per frame,
            // not connection-state-checked).
            state = .ready
            onReady?()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            let continuation = pendingWrite
            pendingWrite = nil
            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume(returning: ())
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let uuid = characteristic.uuid
        let now = Date()
        Task { @MainActor in
            onRawFrame?(uuid, data, now)
        }
    }
}
