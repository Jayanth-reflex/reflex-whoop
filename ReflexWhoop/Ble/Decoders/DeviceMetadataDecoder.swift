import Foundation

/// Thin wrapper around `CborLiteDecoder` for the `fd4b0007` characteristic —
/// see docs/PROTOCOL-GEN5.md's "`fd4b0007` — identified, not decoded" section.
/// Surfaces raw strings rather than named fields: field *meaning* (which
/// string is firmware version vs. hardware codename vs. device ID) was never
/// confirmed, only that the bytes are valid CBOR containing readable text.
enum DeviceMetadataDecoder {
    /// `raw` is the notification's bytes exactly as received on `fd4b0007` —
    /// this characteristic is not `Gen5Envelope`-framed, so callers must not
    /// route it through `FrameReassembler` first.
    static func extractStrings(raw: Data) -> [String] {
        CborLiteDecoder.extractStrings(CborLiteDecoder.decodeSequence(raw))
    }
}
