// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation
import XCTest

@testable import SignalRClient

class BinaryMessageFormatTests: XCTestCase {
    // MARK: Parse
    func testParseZeroLength() throws {
        let data = Data([0x00])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 0)
    }

    func testParseVarInt8() throws {
        let data = Data([0x01, 0x01])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data([0x01]))
    }

    func testParseVarInt16() throws {
        let data = Data([0x81, 0x00, 0x01])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data([0x01]))
    }

    func testParseVarInt24() throws {
        let data = Data([0x81, 0x80, 0x00, 0x01])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data([0x01]))
    }

    func testParseVarInt32() throws {
        let data = Data([0x81, 0x80, 0x80, 0x00, 0x01])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data([0x01]))
    }

    func testParseVarInt40() throws {
        let data = Data([0x81, 0x80, 0x80, 0x80, 0x00, 0x01])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0], Data([0x01]))
    }

    func testMultipleMessages() throws {
        let data = Data([0x01, 0x02, 0x02, 0x01, 0x02, 0x00])
        let messages = try BinaryMessageFormat.parse(data)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0], Data([0x02]))
        XCTAssertEqual(messages[1], Data([0x01, 0x02]))
    }

    func testIncompleteMessageSize() throws {
        let data = Data([0x81])
        do {
            _ = try BinaryMessageFormat.parse(data)
            XCTFail("Should throw when paring incomplete message")
        } catch SignalRError.incompleteMessage {
        }
    }

    func testIncompleteMessage() throws {
        let data = Data([0x80, 0x80, 0x80, 0x80, 0x08, 0x01])
        do {
            _ = try BinaryMessageFormat.parse(data)
            XCTFail("Should throw when paring incomplete message")
        } catch SignalRError.incompleteMessage {
        }
    }

    func testInvalidMessageSizeData() throws {
        let data = Data([0x81, 0x80, 0x80, 0x80, 0x80, 0x00, 0x01])
        do {
            _ = try BinaryMessageFormat.parse(data)
            XCTFail("Should throw when paring invalid message size")
        } catch SignalRError.invalidData(_) {
        }
    }

    func testToLargeData() throws {
        let data = Data([0x81, 0x80, 0x80, 0x80, 0x08, 0x01])
        do {
            _ = try BinaryMessageFormat.parse(data)
            XCTFail("Should throw when paring invalid message size")
        } catch SignalRError.messageBiggerThan2GB {
        }
    }

    // MARK: write
    func testWriteEmpty() throws {
        let data = Data()
        let tpData = try BinaryMessageFormat.write(data)
        XCTAssertEqual(tpData, Data([0x00]))
    }

    func testWriteVar8() throws {
        let data = Data([0x00])
        let tpData = try BinaryMessageFormat.write(data)
        XCTAssertEqual(tpData, Data([0x01, 0x00]))
    }

    func testWriteVar16() throws {
        let data = Data(count: 0x81)
        let tpData = try BinaryMessageFormat.write(data)
        XCTAssertEqual(tpData, Data([0x81, 0x01]) + data)
    }

    func testWriteVar24() throws {
        let data = Data(count: 0x181)
        let tpData = try BinaryMessageFormat.write(data)
        XCTAssertEqual(tpData, Data([0x81, 0x03]) + data)
    }
}
