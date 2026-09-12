import Foundation

/// Speculative decoder for R10 (inner packet_type `0x2B`, docs/design.md:
/// "packet `0x2B`, record `0x0A`, ~1.9 KB per record: HR + IMU"). Gen 5 has
/// never actually been seen sending a `0x2B` frame — no session's
/// `PacketTypeCounts` has shown one yet — so unlike `RealtimeHRDecoder`
/// there is **no confirmed layout to decode**, only docs/design.md's
/// explicit "hypothesis to test, not the answer": Gen 4's type-24 record
/// layout, offsets `[17]`=HR, `[18]`=rr_count, `[19:19+2n]`=RR ms,
/// `[36:48]`=f32×3 accel.
///
/// This exists purely to turn "did a 0x2B frame ever arrive" into "and here's
/// what the Gen 4 hypothesis says it contains, if anything" the moment one
/// does — without needing another code-then-redeploy round trip once the
/// spike catches a real frame. `Sample.isPlausible` requires **both**
/// independent fields (HR in physiological range AND accel magnitude near
/// gravity) to agree before calling it plausible at all, per the same
/// two-independent-signals bar the project used to confirm `0x28`. Never
/// surfaced anywhere outside the Live discovery-spike screen, and always
/// labeled unconfirmed there — see docs/design.md: "Never fabricate a value."
enum R10Decoder {
    struct Sample {
        let candidateHrBpm: UInt8
        let rrIntervalsMs: [Int16]
        let accelG: (x: Float, y: Float, z: Float)
        let accelMagnitudeG: Float
        /// True only when the HR byte is in a physiologically plausible range
        /// AND the accel triple's magnitude is near 1 g — two independent
        /// hypothesis-derived fields agreeing is what makes this worth
        /// showing at all; either alone is coincidence-prone.
        let isPlausible: Bool
    }

    private static let hrRange: ClosedRange<UInt8> = 30...220
    private static let accelMagnitudeRange: ClosedRange<Float> = 0.5...2.0
    private static let maxPlausibleRrCount = 8
    private static let rrRangeMs: ClosedRange<Int16> = 300...2000

    static func decode(inner: Data) -> Sample? {
        guard inner.first == Ble.PacketType.realtimeRaw.rawValue else { return nil }
        let b = [UInt8](inner)
        guard b.count >= 48 else { return nil }

        let hr = b[17]
        let rrCount = min(Int(b[18]), maxPlausibleRrCount)
        var rrIntervals: [Int16] = []
        var offset = 19
        for _ in 0..<rrCount {
            guard offset + 1 < b.count else { break }
            let raw = Int16(b[offset]) | (Int16(b[offset + 1]) << 8)
            rrIntervals.append(raw)
            offset += 2
        }

        let accel = readAccelG(b, at: 36)
        let magnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)

        let hrPlausible = hrRange.contains(hr)
        let accelPlausible = accelMagnitudeRange.contains(magnitude)
        let rrPlausible = rrIntervals.isEmpty || rrIntervals.allSatisfy { rrRangeMs.contains($0) }

        return Sample(
            candidateHrBpm: hr,
            rrIntervalsMs: rrIntervals,
            accelG: accel,
            accelMagnitudeG: magnitude,
            isPlausible: hrPlausible && accelPlausible && rrPlausible
        )
    }

    private static func readAccelG(_ bytes: [UInt8], at offset: Int) -> (x: Float, y: Float, z: Float) {
        func f32(_ o: Int) -> Float {
            guard o + 3 < bytes.count else { return .nan }
            let bits = UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8) | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
            return Float(bitPattern: bits)
        }
        return (f32(offset), f32(offset + 4), f32(offset + 8))
    }
}
