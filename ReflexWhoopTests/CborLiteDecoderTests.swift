import XCTest
@testable import ReflexWhoop

final class CborLiteDecoderTests: XCTestCase {
    func testDecodesShortTextString() {
        // major type 3 (text), length 2, "hi"
        let bytes = Data([0x62, 0x68, 0x69])
        XCTAssertEqual(CborLiteDecoder.decodeSequence(bytes), [.text("hi")])
    }

    func testDecodesArrayOfStringsAndExtractsThem() {
        // array(2) ["abc", "def"]
        let bytes = Data([0x82, 0x63, 0x61, 0x62, 0x63, 0x63, 0x64, 0x65, 0x66])
        let values = CborLiteDecoder.decodeSequence(bytes)
        XCTAssertEqual(values, [.array([.text("abc"), .text("def")])])
        XCTAssertEqual(CborLiteDecoder.extractStrings(values), ["abc", "def"])
    }

    func testDecodesSmallUnsignedInt() {
        XCTAssertEqual(CborLiteDecoder.decodeSequence(Data([0x01])), [.unsigned(1)])
    }

    func testDecodesOneByteUnsignedInt() {
        XCTAssertEqual(CborLiteDecoder.decodeSequence(Data([0x18, 0xFF])), [.unsigned(255)])
    }

    func testTruncatedInputStopsWithoutCrashing() {
        // claims a 3-byte text string but only supplies 1
        XCTAssertEqual(CborLiteDecoder.decodeSequence(Data([0x63, 0x61])), [])
    }

    func testEmptyInputDecodesToNothing() {
        XCTAssertEqual(CborLiteDecoder.decodeSequence(Data()), [])
    }

    func testExtractStringsIgnoresNonTextValues() {
        let values: [CborValue] = [.unsigned(5), .map([(.text("k"), .text("v"))]), .bool(true)]
        XCTAssertEqual(CborLiteDecoder.extractStrings(values), ["k", "v"])
    }
}
