import XCTest
@testable import SignalRClient

class TextMessageFormatTests: XCTestCase {

    func testWrite() {
        let message = "Hello, World!"
        let expectedOutput = "Hello, World!\u{1e}"
        let result = TextMessageFormat.write(message)
        XCTAssertEqual(result, expectedOutput)
    }

    func testParseSingleMessage() {
        let input = "Hello, World!\u{1e}"
        do {
            let result = try TextMessageFormat.parse(input)
            XCTAssertEqual(result, ["Hello, World!"])
        } catch {
            XCTFail("Parsing failed with error: \(error)")
        }
    }

    func testParseMultipleMessages() {
        let input = "Hello\u{1e}World\u{1e}"
        do {
            let result = try TextMessageFormat.parse(input)
            XCTAssertEqual(result, ["Hello", "World"])
        } catch {
            XCTFail("Parsing failed with error: \(error)")
        }
    }

    func testParseIncompleteMessage() {
        let input = "Hello, World!"
        XCTAssertThrowsError(try TextMessageFormat.parse(input)) { error in
            XCTAssertEqual(error as? SignalRError, SignalRError.incompleteMessage)
        }
    }

    func testParseEmptyMessage() {
        let input = "\u{1e}"
        do {
            let result = try TextMessageFormat.parse(input)
            XCTAssertEqual(result, [])
        } catch {
            XCTFail("Parsing failed with error: \(error)")
        }
    }
}