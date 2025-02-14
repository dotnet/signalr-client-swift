import XCTest
@testable import SignalRClient

final class JsonHubProtocolTests: XCTestCase {
    let emptyBinder: InvocationBinder = TestInvocationBinder(binderTypes: [])
    var jsonHubProtocol: JsonHubProtocol!

    override func setUp() {
        super.setUp()
        jsonHubProtocol = JsonHubProtocol()
    }

    override func tearDown() {
        jsonHubProtocol = nil
        super.tearDown()
    }

    func testParseInvocationMessage() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [String.self, Int.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual("arg1", msg.arguments.value![0] as! String)
        XCTAssertEqual(123, msg.arguments.value![1] as! Int)
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithCustomizedClass() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [123, {\"stringVal\": \"str\", \"intVal\": 12345, \"boolVal\": true, \"doubleVal\": 3.14, \"arrayVal\": [\"str2\"], \"dictVal\": {\"key2\": \"str3\"}}]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [Int.self, CustomizedClass.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual(123, msg.arguments.value![0] as! Int)
        guard let customizedClass = msg.arguments.value![1] as? CustomizedClass else {
            XCTFail("Expected CustomizedClass")
            return
        }
        XCTAssertEqual("str", customizedClass.stringVal)
        XCTAssertEqual(12345, customizedClass.intVal)
        XCTAssertEqual(true, customizedClass.boolVal)
        XCTAssertEqual(3.14, customizedClass.doubleVal)
        XCTAssertEqual(1, customizedClass.arrayVal!.count)
        XCTAssertEqual("str2", customizedClass.arrayVal![0])
        XCTAssertEqual("str3", customizedClass.dictVal!["key2"])
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithSomePropertyOptional() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [{\"nokey\":123, \"stringVal\":\"val\"}]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [CustomizedClass.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        guard let customizedClass = msg.arguments.value![0] as? CustomizedClass else {
            XCTFail("Expected CustomizedClass")
            return
        }
        XCTAssertEqual("val", customizedClass.stringVal)
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    private class CustomizedClass: Codable {
        var stringVal: String
        var intVal: Int?
        var boolVal: Bool?
        var doubleVal: Double?
        var arrayVal: [String]?
        var dictVal: [String: String]?
    }

    func testParseInvocationMessageWithArrayElement() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [\"arg1\", [123, 345, 456]]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [String.self, [Int].self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual("arg1", msg.arguments.value![0] as! String)
        guard let array = msg.arguments.value![1] as? [Int] else {
            XCTFail("Expected [Int]")
            return
        }
        XCTAssertEqual(3, array.count)
        XCTAssertEqual(123, array[0])
        XCTAssertEqual(345, array[1])
        XCTAssertEqual(456, array[2])
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithArrayCusomizedClass() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [\"arg1\", [{\"stringVal\":\"val\"}]]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [String.self, [CustomizedClass].self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual("arg1", msg.arguments.value![0] as! String)
        guard let array = msg.arguments.value![1] as? [CustomizedClass] else {
            XCTFail("Expected [CustomizedClass]")
            return
        }
        XCTAssertEqual(1, array.count)
        XCTAssertEqual("val", array[0].stringVal)
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageThrowsForUnmatchedParameterCount() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [String.self])
        XCTAssertThrowsError(try self.jsonHubProtocol.parseMessages(input: .string(input), binder: binder)) { error in
            XCTAssertEqual(error as? SignalRError, SignalRError.invalidData("Invocation provides 2 argument(s) but target expects 1."))
        }
    }

    func testParseInvocationMessageThrowsForNonDecodableClass() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [{\"key\":\"val\"}]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let binder = TestInvocationBinder(binderTypes: [NonDecodableClass.self])
        XCTAssertThrowsError(try self.jsonHubProtocol.parseMessages(input: .string(input), binder: binder)) { error in
            XCTAssertEqual(error as? SignalRError, SignalRError.invalidData("Provided type NonDecodableClass does not conform to Decodable."))
        }
    }

    private class NonDecodableClass {
        var key: String = ""
    }

    func testParseInvocationMessageWithInvocationId() throws {
        let input = "{\"type\": 1, \"invocationId\":\"345\", \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123]}\(TextMessageFormat.recordSeparator)" 
        let binder = TestInvocationBinder(binderTypes: [String.self, Int.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual("arg1", msg.arguments.value![0] as! String)
        XCTAssertEqual(123, msg.arguments.value![1] as! Int)
        XCTAssertEqual("345", msg.invocationId!)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithStream() throws {
        let input = "{\"type\": 1, \"invocationId\":\"345\", \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123], \"streamIds\": [\"1\"]}\(TextMessageFormat.recordSeparator)" 
        let binder = TestInvocationBinder(binderTypes: [String.self, Int.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.value!.count)
        XCTAssertEqual("arg1", msg.arguments.value![0] as! String)
        XCTAssertEqual(123, msg.arguments.value![1] as! Int)
        XCTAssertEqual("345", msg.invocationId!)
        XCTAssertEqual("1", msg.streamIds![0])
    }

    func testParseStreamItemMessage() throws {
        let input = "{\"type\": 2, \"invocationId\":\"345\", \"item\": \"someData\"}\(TextMessageFormat.recordSeparator)" // JSON format for StreamItemMessage
        let binder = TestInvocationBinder(binderTypes: [String.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is StreamItemMessage)
        guard let msg = messages[0] as? StreamItemMessage else {
            XCTFail("Expected StreamItemMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertEqual("someData", msg.item.value as! String)
    }

    func testParseStreamItemMessageWithNull() throws {
        let input = "{\"type\": 2, \"invocationId\":\"345\", \"item\": null}\(TextMessageFormat.recordSeparator)" // JSON format for StreamItemMessage
        let binder = TestInvocationBinder(binderTypes: [String.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is StreamItemMessage)
        guard let msg = messages[0] as? StreamItemMessage else {
            XCTFail("Expected StreamItemMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertNil(msg.item.value)
    }

    func testParseCompletionMessage() throws {
        let input = "{\"type\": 3, \"invocationId\":\"345\", \"result\": \"completionResult\"}\(TextMessageFormat.recordSeparator)" // JSON format for CompletionMessage
        let binder = TestInvocationBinder(binderTypes: [String.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CompletionMessage else {
            XCTFail("Expected CompletionMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertEqual("completionResult", msg.result.value as! String)
    }

    func testParseCompletionMessageWithNull() throws {
        let input = "{\"type\": 3, \"invocationId\":\"345\", \"result\": null}\(TextMessageFormat.recordSeparator)" // JSON format for CompletionMessage
        let binder = TestInvocationBinder(binderTypes: [String.self])
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: binder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CompletionMessage else {
            XCTFail("Expected CompletionMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertNil(msg.result.value)
    }

    func testParseCompletionMessageError() throws {
        let input = "{\"type\": 3, \"invocationId\":\"345\", \"error\": \"Errors\"}\(TextMessageFormat.recordSeparator)" // JSON format for CompletionMessage
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CompletionMessage else {
            XCTFail("Expected CompletionMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertEqual("Errors", msg.error)
    }

    func testParseCancelInvocation() throws {
        let input = "{\"type\": 5, \"invocationId\":\"345\"}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CancelInvocationMessage else {
            XCTFail("Expected CancelInvocationMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
    }

    func testParsePing() throws {
        let input = "{\"type\": 6}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? PingMessage else {
            XCTFail("Expected PingMessage")
            return
        }
    }

    func testParseCloseMessage() throws {
        let input = "{\"type\": 7, \"error\":\"Connection closed because of an error!\", \"allowReconnect\": true}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CloseMessage else {
            XCTFail("Expected CloseMessage")
            return
        }
        XCTAssertEqual("Connection closed because of an error!", msg.error!)
        XCTAssertTrue(msg.allowReconnect!)
    }

    func testParseAckMessage() throws {
        let input = "{\"type\": 8, \"sequenceId\":1394}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? AckMessage else {
            XCTFail("Expected AckMessage")
            return
        }
        XCTAssertEqual(1394, msg.sequenceId)
    }

    func testParseSequenceMessage() throws {
        let input = "{\"type\": 9, \"sequenceId\":1394}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? SequenceMessage else {
            XCTFail("Expected SequenceMessage")
            return
        }
        XCTAssertEqual(1394, msg.sequenceId)
    }

    func testParseUnknownMessageType() throws {
        let input = "{\"type\": 99}\(TextMessageFormat.recordSeparator)" // Unknown message type
        let messages = try jsonHubProtocol.parseMessages(input: .string(input), binder: emptyBinder)

        XCTAssertEqual(messages.count, 0)
    }

    func testWriteInvocationMessage() throws {
        let message = InvocationMessage(
            target: "testTarget",
            arguments: AnyEncodableArray(["arg1", 123]),
            streamIds: ["456"],
            headers: ["key1": "value1", "key2": "value2"],
            invocationId: "123"
        )

        try verifyWriteMessage(message: message, expectedJson: """
        {"streamIds":["456"],"type":1,"headers":{"key2":"value2","key1":"value1"},"target":"testTarget","arguments":["arg1",123],"invocationId":"123"}
        """)
    }

    func testWriteInvocationMessageWithAllElement() throws {
        let message = InvocationMessage(
            target: "testTarget",
            arguments: AnyEncodableArray(["arg1", // string
                                          123, // int
                                          3.14, // double
                                          true, // bool
                                          ["array1", 456], // array
                                          ["key1": "value1", "key2": "value2"], // dictionary
                                          CustomizedEncodingClass(stringVal: "str", intVal: 12345, doubleVal: 3.14, boolVal: true)]),

            streamIds: ["456"],
            headers: ["key1": "value1", "key2": "value2"],
            invocationId: "123"
        )

        try verifyWriteMessage(message: message, expectedJson: """
        {"streamIds":["456"],"type":1,"headers":{"key2":"value2","key1":"value1"},"target":"testTarget","arguments":["arg1",123,3.14,true,["array1",456],{"key1":"value1","key2":"value2"},{"stringVal":"str","intVal":12345,"doubleVal":3.14,"boolVal":true}],"invocationId":"123"}
        """)
    }

    private struct CustomizedEncodingClass: Encodable {
        var stringVal: String = ""
        var intVal: Int = 0
        var doubleVal: Double = 0.0
        var boolVal: Bool = false
    }

    func testWriteStreamItemMessage() throws {
        let message = StreamItemMessage(invocationId: "123", item: AnyEncodable("someData"), headers: ["key1": "value1", "key2": "value2"])

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":2,"item":"someData","invocationId":"123","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteStreamItemMessage2() throws {
        let message = StreamItemMessage(invocationId: "123", item: AnyEncodable(["someData", 123]), headers: ["key1": "value1", "key2": "value2"])

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":2,"item":["someData",123],"invocationId":"123","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteStreamItemMessage3() throws {
        let message = StreamItemMessage(invocationId: "123", item: AnyEncodable(nil), headers: ["key1": "value1", "key2": "value2"])

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":2,"item":null,"invocationId":"123","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteCompletionMessage() throws {
        let message = CompletionMessage(
            invocationId: "123",
            error: nil,
            result: AnyEncodable("completionResult"),
            headers: ["key1": "value1", "key2": "value2"]
        )

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":3,"invocationId":"123","result":"completionResult","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteCompletionMessageWithNull() throws {
        let message = CompletionMessage(
            invocationId: "123",
            error: nil,
            result: AnyEncodable(nil),
            headers: ["key1": "value1", "key2": "value2"]
        )

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":3,"invocationId":"123","result":null,"headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteStreamInvocationMessage() throws {
        let message = StreamInvocationMessage(
            invocationId: "streamId123",
            target: "streamTarget",
            arguments: AnyEncodableArray(["arg1", 456]),
            streamIds: ["123"],
            headers: ["key1": "value1", "key2": "value2"]
        )

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":4,"target":"streamTarget","arguments":["arg1",456],"invocationId":"streamId123","streamIds":["123"],"headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteCancelInvocationMessage() throws {
        let message = CancelInvocationMessage(invocationId: "cancel123", headers: ["key1": "value1", "key2": "value2"])

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":5,"invocationId":"cancel123","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWritePingMessage() throws {
        let message = PingMessage()

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":6}
        """)
    }

    func testWriteCloseMessage() throws {
        let message = CloseMessage(error: "Connection closed", allowReconnect: true)

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":7,"error":"Connection closed","allowReconnect":true}
        """)
    }

    func testWriteAckMessage() throws {
        let message = AckMessage(sequenceId: 123)

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":8,"sequenceId":123}
        """)
    }

    func testWriteSequenceMessage() throws {
        let message = SequenceMessage(sequenceId: 1001)

        try verifyWriteMessage(message: message, expectedJson: """
        {"type":9,"sequenceId":1001}
        """)
    }

    // Helper function to verify JSON serialization of messages
    private func verifyWriteMessage(message: HubMessage, expectedJson: String) throws {
        let output = try jsonHubProtocol.writeMessage(message: message)

        if case var .string(outputString) = output {
            outputString = String(outputString.dropLast()) // Remove last 0x1E character if present

            // Convert output and expected JSON strings to dictionaries for comparison
            let outputJson = try JSONSerialization.jsonObject(with: outputString.data(using: .utf8)!) as! NSDictionary
            let expectedJsonObject = try JSONSerialization.jsonObject(with: expectedJson.data(using: .utf8)!) as! NSDictionary

            XCTAssertEqual(outputJson, expectedJsonObject, "The JSON output does not match the expected JSON structure for \(message)")
        } else {
            XCTFail("Expected output to be a string")
        }
    }
}

class TestInvocationBinder: InvocationBinder, @unchecked Sendable {
    private let binderTypes: [Any.Type]

    init(binderTypes: [Any.Type]) {
        self.binderTypes = binderTypes
    }

    func getReturnType(invocationId: String) -> Any.Type? {
        return binderTypes.first
    }

    func getParameterTypes(methodName: String) -> [Any.Type] {
        return binderTypes
    }

    func getStreamItemType(streamId: String) -> Any.Type? {
        return binderTypes.first
    }
}
