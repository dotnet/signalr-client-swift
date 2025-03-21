// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest
@testable import SignalRClient

class HandshakeProtocolTests: XCTestCase {

    func testWriteHandshakeRequest() throws {
        let handshakeRequest = HandshakeRequestMessage(protocol: "json", version: 1)
        let result: String = try HandshakeProtocol.writeHandshakeRequest(handshakeRequest: handshakeRequest)

        XCTAssertTrue(result.hasSuffix("\u{1e}"))

        let resultWithoutPrefix = result.dropLast()

        let resultJson = try JSONSerialization.jsonObject(with: resultWithoutPrefix.data(using: .utf8)!, options: []) as? [String: Any]
        XCTAssertEqual("json", resultJson?["protocol"] as? String)
        XCTAssertEqual(1, resultJson?["version"] as? Int)
    }

    func testParseHandshakeResponseWithValidString() throws {
        let responseString = "{\"error\":null,\"minorVersion\":1}\u{1e}"
        let data = StringOrData.string(responseString)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        XCTAssertNil(remainingData)
        XCTAssertNil(responseMessage.error)
        XCTAssertEqual(responseMessage.minorVersion, 1)
    }

    func testParseHandshakeResponseWithValidString2() throws {
        let responseString = "{}\u{1e}"
        let data = StringOrData.string(responseString)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        XCTAssertNil(remainingData)
        XCTAssertNil(responseMessage.error)
        XCTAssertNil(responseMessage.minorVersion)
    }

    func testParseHandshakeResponseWithValidData() throws {
        let responseString = "{\"error\":null,\"minorVersion\":1}\u{1e}"
        let responseData = responseString.data(using: .utf8)!
        let data = StringOrData.data(responseData)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        XCTAssertNil(remainingData)
        XCTAssertNil(responseMessage.error)
        XCTAssertEqual(responseMessage.minorVersion, 1)
    }

    func testParseHandshakeResponseWithRemainingStringData() throws {
        let responseString = "{\"error\":null,\"minorVersion\":1}\u{1e}remaining"
        let data = StringOrData.string(responseString)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        if case let .string(remainingData) = remainingData {
            XCTAssertEqual(remainingData, "remaining")
        } else {
            XCTFail("Remaining data should be string")
        }
        XCTAssertNil(responseMessage.error)
        XCTAssertEqual(responseMessage.minorVersion, 1)
    }

    func testParseHandshakeResponseWithRemainingBinaryData() throws {
        let responseString = "{\"error\":null,\"minorVersion\":1}\u{1e}remaining"
        let responseData = responseString.data(using: .utf8)!
        let data = StringOrData.data(responseData)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        if case let .data(remainingData) = remainingData {
            XCTAssertEqual(remainingData, "remaining".data(using: .utf8)!)
        } else {
            XCTFail("Remaining data should be data")
        }
        XCTAssertNil(responseMessage.error)
        XCTAssertEqual(responseMessage.minorVersion, 1)
    }

    func testParseHandshakeResponseWithError() throws {
        let responseString = "{\"error\":\"Some error\",\"minorVersion\":null}\u{1e}"
        let data = StringOrData.string(responseString)
        let (remainingData, responseMessage) = try HandshakeProtocol.parseHandshakeResponse(data: data)

        XCTAssertNil(remainingData)
        XCTAssertEqual(responseMessage.error, "Some error")
        XCTAssertNil(responseMessage.minorVersion)
    }

    func testParseHandshakeResponseWithIncompleteMessage() {
        let responseString = "{\"error\":null,\"minorVersion\":1}"
        let data = StringOrData.string(responseString)

        XCTAssertThrowsError(try HandshakeProtocol.parseHandshakeResponse(data: data)) { error in
            XCTAssertEqual(error as? SignalRError, SignalRError.incompleteMessage)
        }
    }

    func testParseHandshakeResponseWithNormalMessage() {
        let responseString = "{\"type\":1,\"target\":\"Send\",\"arguments\":[]}\u{1e}"
        let data = StringOrData.string(responseString)

        XCTAssertThrowsError(try HandshakeProtocol.parseHandshakeResponse(data: data)) { error in
            XCTAssertEqual(error as? SignalRError, SignalRError.expectedHandshakeResponse)
        }
    }
}