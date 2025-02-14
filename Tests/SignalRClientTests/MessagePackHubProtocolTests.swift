import Foundation
import XCTest

@testable import SignalRClient

class MessagePackHubProtocolTests: XCTestCase {
    func testInvocationMessage() throws {
        let data = Data([
            0x96, 0x01, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0xa6, 0x6d, 0x65, 0x74,
            0x68, 0x6f, 0x64, 0x91, 0x2a, 0x90,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! InvocationMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertEqual(message.target, "method")
        XCTAssertEqual(message.arguments.value?.count, 1)
        XCTAssertEqual(message.arguments.value?[0] as? Int, 42)
        XCTAssertEqual(message.streamIds, [])

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testParseStreamInvocationMessage() throws {
        let data = Data([
            0x96, 0x04, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0xa6, 0x6d, 0x65, 0x74,
            0x68, 0x6f, 0x64, 0x91, 0x2a, 0x90,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
        XCTAssertNil(message)
    }

    func testWriteInvocationMessage() throws {
        let data = Data([
            0x96, 0x04, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0xa6, 0x6d, 0x65, 0x74,
            0x68, 0x6f, 0x64, 0x91, 0x2a, 0x90,
        ])
        let msgpack = MessagePackHubProtocol()
        switch try msgpack.writeMessage(
            message: StreamInvocationMessage(
                invocationId: "xyz", target: "method",
                arguments: AnyEncodableArray([42]), streamIds: [],
                headers: [:]))
        {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testStreamItemMessage() throws {
        let data = Data([
            0x94, 0x02, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x2a,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! StreamItemMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertEqual(message.item.value as? Int, 42)

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testCompletionMessageError() throws {
        let data = Data([
            0x95, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x01, 0xa5, 0x45, 0x72,
            0x72, 0x6f, 0x72,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CompletionMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertEqual(message.error, "Error")

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testCompletionMessageVoid() throws {
        let data = Data([
            0x94, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x02,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CompletionMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertNil(message.error)
        XCTAssertNil(message.result.value)

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
//            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
            // Encoded to resultKind = 3
            XCTAssertEqual(d, try BinaryMessageFormat.write(Data([
                0x95, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x03,0xc0
            ])))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testCompletionMessageResult() throws {
        let data = Data([
            0x95, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x03, 0x2a,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CompletionMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertNil(message.error)
        XCTAssertEqual(message.result.value as? Int, 42)

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testCompletionMessageResultNoBinder() throws {
        let data = Data([
            0x95, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x03, 0x2a,
        ])
        let binder = TestInvocationBinder(binderTypes: [])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CompletionMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertNil(message.error)
        XCTAssertNil(message.result.value)
    }

    func testCompletionMessageResultNotDecodable() throws {
        let data = Data([
            0x95, 0x03, 0x80, 0xa3, 0x78, 0x79, 0x7a, 0x03, 0x2a,
        ])
        let binder = TestInvocationBinder(binderTypes: [LogHandler.self])
        let msgpack = MessagePackHubProtocol()

        do {
            try msgpack.parseMessage(message: data, binder: binder)
            XCTFail("Should throw when paring not decodable")
        }catch SignalRError.invalidData(let errmsg){
            XCTAssertTrue(errmsg.contains("Decodable"))
        }
    }

    func testCancelInvocationMessage() throws {
        let data = Data([
            0x93, 0x05, 0x80, 0xa3, 0x78, 0x79, 0x7a,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CancelInvocationMessage
        XCTAssertEqual(message.headers, [:])
        XCTAssertEqual(message.invocationId, "xyz")

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testPingMessage() throws {
        let data = Data([
            0x91, 0x06,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! PingMessage

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testParseCloseMessageWithoutReconnect() throws {
        let data = Data([
            0x92, 0x07, 0xa3, 0x78, 0x79, 0x7a,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CloseMessage
        XCTAssertEqual(message.error, "xyz")
        XCTAssertNil(message.allowReconnect)
    }

    func testCloseMessageWithReconnect() throws {
        let data = Data([
            0x93, 0x07, 0xa3, 0x78, 0x79, 0x7a, 0xc3,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! CloseMessage
        XCTAssertEqual(message.error, "xyz")
        XCTAssertEqual(message.allowReconnect, true)
        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            // allowReconnect field is not encoded at client side
            XCTAssertEqual(
                d,
                try BinaryMessageFormat.write(
                    Data([
                        0x92, 0x07, 0xa3, 0x78, 0x79, 0x7a,
                    ])))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testAckMessage() throws {
        let data = Data([
            0x92, 0x08, 0xcc, 0x24,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! AckMessage
        XCTAssertEqual(message.sequenceId, 36)
        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(
                d, try BinaryMessageFormat.write(Data([0x92, 0x08, 0x24])))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testSequenceMessage() throws {
        let data = Data([
            0x92, 0x09, 0xcc, 0x13,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! SequenceMessage
        XCTAssertEqual(message.sequenceId, 19)
        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(
                d, try BinaryMessageFormat.write(Data([0x92, 0x09, 0x13])))
        default:
            XCTFail("Wrong encoded typed")
        }
    }

    func testInvocationMessageWithHeaders() throws {
        let data = Data([
            0x96, 0x01, 0x81, 0xa1, 0x78, 0xa1, 0x79,
            0xa3, 0x78, 0x79, 0x7a, 0xa6, 0x6d, 0x65, 0x74, 0x68, 0x6f, 0x64,
            0x91, 0x2a, 0x90,
        ])
        let binder = TestInvocationBinder(binderTypes: [Int.self])
        let msgpack = MessagePackHubProtocol()
        let message =
            try msgpack.parseMessage(message: data, binder: binder)
            as! InvocationMessage
        XCTAssertEqual(message.headers?.count, 1)
        XCTAssertEqual(message.headers?["x"], "y")
        XCTAssertEqual(message.invocationId, "xyz")
        XCTAssertEqual(message.target, "method")
        XCTAssertEqual(message.arguments.value?.count, 1)
        XCTAssertEqual(message.arguments.value?[0] as? Int, 42)
        XCTAssertEqual(message.streamIds, [])

        switch try msgpack.writeMessage(message: message) {
        case .data(let d):
            XCTAssertEqual(d, try BinaryMessageFormat.write(data))
        default:
            XCTFail("Wrong encoded typed")
        }
    }
}
