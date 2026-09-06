import XCTest
@testable import ReflexWhoop

final class ChunkCodecTests: XCTestCase {
    // MARK: - Edge cases

    func testEmptyArrayRoundTrips() {
        assertRoundTrip([])
    }

    func testSingleValueRoundTrips() {
        assertRoundTrip([42])
        assertRoundTrip([-42])
        assertRoundTrip([0])
    }

    func testConstantSeriesRoundTrips() {
        // All-zero deltas — the case delta encoding is built for.
        assertRoundTrip(Array(repeating: 72, count: 1000))
    }

    func testMonotonicIncreasingRoundTrips() {
        assertRoundTrip((0..<1000).map { Int64($0) })
    }

    func testAlternatingSignLargeDeltasRoundTrips() {
        var values: [Int64] = []
        for i in 0..<500 {
            values.append(i % 2 == 0 ? 1_000_000 : -1_000_000)
        }
        assertRoundTrip(values)
    }

    func testExtremeValuesNearInt64BoundaryRoundTrip() {
        // Deltas between adjacent extreme values can themselves overflow Int64;
        // the codec must not crash even though this never occurs with real sensor
        // data (documented assumption in ChunkCodec's header comment).
        assertRoundTrip([Int64.min, Int64.max, Int64.min, 0, Int64.max])
    }

    func testZigzagRoundTripsAllSampledValues() {
        let samples: [Int64] = [0, 1, -1, 2, -2, 1000, -1000, Int64.max, Int64.min, Int64.max - 1, Int64.min + 1]
        for n in samples {
            let z = ChunkCodec.zigzagEncode(n)
            XCTAssertEqual(ChunkCodec.zigzagDecode(z), n, "zigzag round-trip failed for \(n)")
        }
    }

    func testVarintRoundTripsAcrossByteLengths() {
        // 0, 127 (1 byte), 128 (2 bytes), and boundaries up to UInt64.max (10 bytes).
        let samples: [UInt64] = [0, 127, 128, 16383, 16384, UInt64(UInt32.max), UInt64.max]
        for v in samples {
            var data = Data()
            ChunkCodec.appendVarint(v, to: &data)
            let (decoded, next) = ChunkCodec.readVarint(data, from: data.startIndex)
            XCTAssertEqual(decoded, v)
            XCTAssertEqual(next, data.endIndex)
        }
    }

    // MARK: - Randomized round-trip, realistic sensor ranges

    func testRandomizedRealisticHeartRateSeriesRoundTrips() {
        var rng = SeededGenerator(seed: 1)
        // HR in bpm, realistic random walk 40-200, exactly the shape a real channel takes.
        var values: [Int64] = []
        var current: Int64 = 70
        for _ in 0..<10_000 {
            current = max(40, min(200, current + Int64.random(in: -3...3, using: &rng)))
            values.append(current)
        }
        assertRoundTrip(values)
    }

    func testRandomizedWideRangeRoundTrips() {
        var rng = SeededGenerator(seed: 2)
        let values = (0..<5000).map { _ in Int64.random(in: -1_000_000...1_000_000, using: &rng) }
        assertRoundTrip(values)
    }

    // MARK: - Compression wrapper round-trip

    func testCompressionRoundTripsForEachCodec() {
        let (_, encoded) = ChunkCodec.encode((0..<2000).map { Int64($0 % 50) })
        for codec: ChunkBlobCodec in [.lzfse, .zlib, .none] {
            let (usedCodec, compressed) = ChunkCompression.compress(encoded, using: codec)
            let decompressed = ChunkCompression.decompress(compressed, using: usedCodec, expectedSize: encoded.count)
            XCTAssertEqual(decompressed, encoded, "compression round-trip failed for \(codec)")
        }
    }

    func testCompressionHandlesEmptyData() {
        let (codec, compressed) = ChunkCompression.compress(Data(), using: .lzfse)
        let decompressed = ChunkCompression.decompress(compressed, using: codec, expectedSize: 0)
        XCTAssertEqual(decompressed, Data())
    }

    func testCompressionRetriesWhenSizeHintTooSmall() {
        let original = Data((0..<10_000).map { UInt8($0 % 256) })
        let (codec, compressed) = ChunkCompression.compress(original, using: .lzfse)
        // Deliberately wrong (tiny) hint — decompress must still succeed via the
        // doubling-buffer retry, not just return truncated garbage.
        let decompressed = ChunkCompression.decompress(compressed, using: codec, expectedSize: 4)
        XCTAssertEqual(decompressed, original)
    }

    // MARK: - Helpers

    private func assertRoundTrip(_ values: [Int64], file: StaticString = #filePath, line: UInt = #line) {
        let (encoding, bytes) = ChunkCodec.encode(values)
        let decoded = ChunkCodec.decode(encoding: encoding, bytes: bytes, count: values.count)
        XCTAssertEqual(decoded, values, "round-trip mismatch for encoding \(encoding)", file: file, line: line)
    }
}

/// Deterministic RNG so randomized tests are reproducible across runs and CI.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
