import Foundation

/// Minimal CBOR (RFC 7049) reader, just enough to parse `fd4b0007`'s
/// device-metadata payload (docs/PROTOCOL-GEN5.md: "identified as CBOR ...
/// length-prefixed text strings decode directly to readable content"). That
/// characteristic does not use `Gen5Envelope` framing at all, so this decodes
/// the raw notification bytes directly.
///
/// Unlike the Gen5 envelope work, CBOR is a public, fully-specified format —
/// no reverse-engineering hypothesis involved, so this can be trusted as soon
/// as it parses without error. What's still unconfirmed is only the *meaning*
/// of each field (docs/PROTOCOL-GEN5.md: "not a priority to fully parse"),
/// which is why `DeviceMetadataDecoder` surfaces raw values rather than named
/// fields.
enum CborValue: Equatable {
    case unsigned(UInt64)
    case negative(Int64) // already includes the -1-n transform
    case bytes(Data)
    case text(String)
    case array([CborValue])
    case map([(CborValue, CborValue)])
    case bool(Bool)
    case null
    case float(Double)

    static func == (lhs: CborValue, rhs: CborValue) -> Bool {
        switch (lhs, rhs) {
        case (.unsigned(let a), .unsigned(let b)): return a == b
        case (.negative(let a), .negative(let b)): return a == b
        case (.bytes(let a), .bytes(let b)): return a == b
        case (.text(let a), .text(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.float(let a), .float(let b)): return a == b
        case (.map(let a), .map(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }
}

enum CborLiteDecoder {
    /// Decodes every top-level CBOR item found in `data`, in order, stopping
    /// (and returning what was decoded so far) at the first malformed byte
    /// rather than throwing — this is diagnostic tooling reading live BLE
    /// bytes, not a trusted wire format; partial results still tell us
    /// something about a frame we've never seen before.
    static func decodeSequence(_ data: Data) -> [CborValue] {
        var reader = Reader(bytes: [UInt8](data))
        var items: [CborValue] = []
        while reader.hasMore {
            guard let value = reader.readValue() else { break }
            items.append(value)
        }
        return items
    }

    /// Flattens any decoded value tree into just its text strings, in
    /// depth-first order — that's the entire useful surface identified so far
    /// per `docs/PROTOCOL-GEN5.md` ("build/version string, hardware codename,
    /// internal codename, a long ID string").
    static func extractStrings(_ values: [CborValue]) -> [String] {
        var out: [String] = []
        func visit(_ value: CborValue) {
            switch value {
            case .text(let s): out.append(s)
            case .array(let items): items.forEach(visit)
            case .map(let pairs):
                for (k, v) in pairs { visit(k); visit(v) }
            default: break
            }
        }
        values.forEach(visit)
        return out
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var hasMore: Bool { index < bytes.count }

        mutating func readValue() -> CborValue? {
            guard index < bytes.count else { return nil }
            let initial = bytes[index]
            index += 1
            let majorType = initial >> 5
            let infoBits = initial & 0x1F

            switch majorType {
            case 0: // unsigned int
                guard let n = readArgument(infoBits) else { return nil }
                return .unsigned(n)
            case 1: // negative int: value = -1 - n
                guard let n = readArgument(infoBits) else { return nil }
                return .negative(-1 - Int64(bitPattern: n))
            case 2: // byte string
                guard let len = readArgument(infoBits), let slice = readBytes(Int(len)) else { return nil }
                return .bytes(Data(slice))
            case 3: // text string
                guard let len = readArgument(infoBits), let slice = readBytes(Int(len)) else { return nil }
                return .text(String(decoding: slice, as: UTF8.self))
            case 4: // array
                guard let count = readArgument(infoBits) else { return nil }
                var items: [CborValue] = []
                for _ in 0..<count {
                    guard let item = readValue() else { return nil }
                    items.append(item)
                }
                return .array(items)
            case 5: // map
                guard let count = readArgument(infoBits) else { return nil }
                var pairs: [(CborValue, CborValue)] = []
                for _ in 0..<count {
                    guard let key = readValue(), let value = readValue() else { return nil }
                    pairs.append((key, value))
                }
                return .map(pairs)
            case 7: // simple/float/break
                switch infoBits {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 25: return readFloat16()
                case 26: return readFloat32()
                case 27: return readFloat64()
                default: return nil
                }
            default:
                return nil
            }
        }

        /// Reads the argument that follows the initial byte's low 5 bits.
        /// Indefinite-length (infoBits == 31) is not supported — nothing seen
        /// in the one confirmed CBOR sample used it, and treating it as
        /// "unparseable" (return nil, stop) is safer than guessing at a
        /// terminator scheme untested against real bytes.
        mutating func readArgument(_ infoBits: UInt8) -> UInt64? {
            switch infoBits {
            case 0...23:
                return UInt64(infoBits)
            case 24:
                guard let b = readBytes(1) else { return nil }
                return UInt64(b[0])
            case 25:
                guard let b = readBytes(2) else { return nil }
                return b.reduce(0) { ($0 << 8) | UInt64($1) }
            case 26:
                guard let b = readBytes(4) else { return nil }
                return b.reduce(0) { ($0 << 8) | UInt64($1) }
            case 27:
                guard let b = readBytes(8) else { return nil }
                return b.reduce(0) { ($0 << 8) | UInt64($1) }
            default:
                return nil // 28-30 reserved, 31 indefinite-length — unsupported
            }
        }

        mutating func readBytes(_ count: Int) -> [UInt8]? {
            guard count >= 0, index + count <= bytes.count else { return nil }
            let slice = Array(bytes[index..<(index + count)])
            index += count
            return slice
        }

        mutating func readFloat16() -> CborValue? {
            guard let b = readBytes(2) else { return nil }
            let bits = (UInt16(b[0]) << 8) | UInt16(b[1])
            let sign = (bits & 0x8000) != 0 ? -1.0 : 1.0
            let exponent = Int((bits >> 10) & 0x1F)
            let fraction = Double(bits & 0x3FF)
            let value: Double
            if exponent == 0 {
                value = sign * (fraction / 1024.0) * pow(2.0, -14)
            } else if exponent == 31 {
                value = fraction == 0 ? sign * .infinity : .nan
            } else {
                value = sign * (1.0 + fraction / 1024.0) * pow(2.0, Double(exponent - 15))
            }
            return .float(value)
        }

        mutating func readFloat32() -> CborValue? {
            guard let b = readBytes(4) else { return nil }
            let bits = b.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            return .float(Double(Float(bitPattern: bits)))
        }

        mutating func readFloat64() -> CborValue? {
            guard let b = readBytes(8) else { return nil }
            let bits = b.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return .float(Double(bitPattern: bits))
        }
    }
}
