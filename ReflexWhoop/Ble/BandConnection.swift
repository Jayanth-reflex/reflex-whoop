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
    enum ConnectionState: Equatable {
        case idle
        case unavailable(String) // powered off / unauthorized / unsupported
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

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var sequenceCounter: UInt8 = 0

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func disconnect() {
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        state = .idle
    }

    /// Builds and sends one command frame. `OpcodeAllowlist.assertAllowed` is
    /// called first and unconditionally — this is the only place in the
    /// codebase that writes to `writeCharacteristicUUID`, so this one check
    /// guards every outgoing command the app can ever send.
    func send(opcode: Ble.AllowedOpcode, body: Data = Data()) throws {
        try OpcodeAllowlist.assertAllowed(opcode.rawValue)
        guard let peripheral, let writeCharacteristic else {
            throw BandConnectionError.notReady
        }
        sequenceCounter &+= 1
        var inner = Data([Ble.PacketType.command.rawValue, sequenceCounter, opcode.rawValue])
        inner.append(body)
        let frame = Gen5Envelope.encode(field: 0, inner: inner)
        // Gen 5 requires write-with-response — write-without-response is a
        // documented no-op (docs/design.md's Gen4/Gen5 diff table).
        peripheral.writeValue(frame, for: writeCharacteristic, type: .withResponse)
    }

    enum BandConnectionError: Error {
        case notReady
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
                state = .unavailable("Bluetooth is off")
            case .unauthorized:
                state = .unavailable("Bluetooth permission denied")
            case .unsupported:
                state = .unavailable("Bluetooth not supported")
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
            self.peripheral = nil
            writeCharacteristic = nil
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
