import XCTest
@testable import SignalRClient

final class JsonHubProtocolTests: XCTestCase {
    
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
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.count)
        XCTAssertEqual("arg1", msg.arguments[0].value as! String)
        XCTAssertEqual(123, msg.arguments[1].value as! Int)
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessage2() throws {
        let input = "{\"type\": 1, \"target\": \"testTarget\", \"arguments\": [123]}\(TextMessageFormat.recordSeparator)" // JSON format for InvocationMessage
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(1, msg.arguments.count)
        XCTAssertEqual("arg1", msg.arguments[0].value as! String)
        XCTAssertEqual(123, msg.arguments[1].value as! Int)
        XCTAssertNil(msg.invocationId)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithInvocationId() throws {
        let input = "{\"type\": 1, \"invocationId\":\"345\", \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123]}\(TextMessageFormat.recordSeparator)" 
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.count)
        XCTAssertEqual("arg1", msg.arguments[0].value as! String)
        XCTAssertEqual(123, msg.arguments[1].value as! Int)
        XCTAssertEqual("345", msg.invocationId!)
        XCTAssertNil(msg.streamIds)
    }

    func testParseInvocationMessageWithStream() throws {
        let input = "{\"type\": 1, \"invocationId\":\"345\", \"target\": \"testTarget\", \"arguments\": [\"arg1\", 123], \"streamIds\": [\"1\"]}\(TextMessageFormat.recordSeparator)" 
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is InvocationMessage)
        let msg = messages[0] as! InvocationMessage
        XCTAssertEqual("testTarget", msg.target)
        XCTAssertEqual(2, msg.arguments.count)
        XCTAssertEqual("arg1", msg.arguments[0].value as! String)
        XCTAssertEqual(123, msg.arguments[1].value as! Int)
        XCTAssertEqual("345", msg.invocationId!)
        XCTAssertEqual("1", msg.streamIds![0])
    }

    func testParseStreamItemMessage() throws {
        let input = "{\"type\": 2, \"invocationId\":\"345\", \"item\": \"someData\"}\(TextMessageFormat.recordSeparator)" // JSON format for StreamItemMessage
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0] is StreamItemMessage)
        guard let msg = messages[0] as? StreamItemMessage else {
            XCTFail("Expected StreamItemMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertEqual("someData", msg.item!.value as! String)
    }

    func testParseCompletionMessage() throws {
        let input = "{\"type\": 3, \"invocationId\":\"345\", \"result\": \"completionResult\"}\(TextMessageFormat.recordSeparator)" // JSON format for CompletionMessage
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CompletionMessage else {
            XCTFail("Expected CompletionMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
        XCTAssertEqual("completionResult", msg.result?.value as! String)
    }

    func testParseCompletionMessageError() throws {
        let input = "{\"type\": 3, \"invocationId\":\"345\", \"error\": \"Errors\"}\(TextMessageFormat.recordSeparator)" // JSON format for CompletionMessage
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
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
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? CancelInvocationMessage else {
            XCTFail("Expected CancelInvocationMessage")
            return
        }
        XCTAssertEqual("345", msg.invocationId)
    }

    func testParsePing() throws {
        let input = "{\"type\": 6}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? PingMessage else {
            XCTFail("Expected PingMessage")
            return
        }
    }

    func testParseCloseMessage() throws {
        let input = "{\"type\": 7, \"error\":\"Connection closed because of an error!\", \"allowReconnect\": true}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
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
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? AckMessage else {
            XCTFail("Expected AckMessage")
            return
        }
        XCTAssertEqual(1394, msg.sequenceId)
    }

    func testParseSequenceMessage() throws {
        let input = "{\"type\": 9, \"sequenceId\":1394}\(TextMessageFormat.recordSeparator)"
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 1)
        guard let msg = messages[0] as? SequenceMessage else {
            XCTFail("Expected SequenceMessage")
            return
        }
        XCTAssertEqual(1394, msg.sequenceId)
    }

    func testParseUnknownMessageType() throws {
        let input = "{\"type\": 99}\(TextMessageFormat.recordSeparator)" // Unknown message type
        let messages = try jsonHubProtocol.parseMessages(input: .string(input))
        
        XCTAssertEqual(messages.count, 0)
    }

    func testWriteInvocationMessage() throws {
        let message = InvocationMessage(
            target: "testTarget",
            arguments: [AnyCodable("arg1"), AnyCodable(123)],
            streamIds: ["456"],
            headers: ["key1": "value1", "key2": "value2"],
            invocationId: "123"
        )
        
        try verifyWriteMessage(message: message, expectedJson: """
        {"streamIds":["456"],"type":1,"headers":{"key2":"value2","key1":"value1"},"target":"testTarget","arguments":["arg1",123],"invocationId":"123"}
        """)
    }

    func testWriteStreamItemMessage() throws {
        let message = StreamItemMessage(invocationId: "123", item: AnyCodable("someData"), headers: ["key1": "value1", "key2": "value2"])
        
        try verifyWriteMessage(message: message, expectedJson: """
        {"type":2,"item":"someData","invocationId":"123","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteCompletionMessage() throws {
        let message = CompletionMessage(
            invocationId: "123",
            error: nil,
            result: AnyCodable("completionResult"),
            headers: ["key1": "value1", "key2": "value2"]
        )
        
        try verifyWriteMessage(message: message, expectedJson: """
        {"type":3,"invocationId":"123","result":"completionResult","headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteStreamInvocationMessage() throws {
        let message = StreamInvocationMessage(
            invocationId: "streamId123",
            target: "streamTarget",
            arguments: [AnyCodable("arg1"), AnyCodable(456)],
            streamIds: ["123"],
            headers: ["key1": "value1", "key2": "value2"]
        )
        
        try verifyWriteMessage(message: message, expectedJson: """
        {"type":4,"target":"streamTarget","arguments":["arg1",456],"invocationId":"streamId123","streamIds":["123"],"headers":{"key2":"value2","key1":"value1"}}
        """)
    }

    func testWriteCancelInvocationMessage() throws {
        let message = CancelInvocationMessage(invocationId: "cancel123",headers: ["key1": "value1", "key2": "value2"])
        
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
            outputString = String(outputString.dropLast())  // Remove last 0x1E character if present
            
            // Convert output and expected JSON strings to dictionaries for comparison
            let outputJson = try JSONSerialization.jsonObject(with: outputString.data(using: .utf8)!) as! NSDictionary
            let expectedJsonObject = try JSONSerialization.jsonObject(with: expectedJson.data(using: .utf8)!) as! NSDictionary
            
            XCTAssertEqual(outputJson, expectedJsonObject, "The JSON output does not match the expected JSON structure for \(message)")
        } else {
            XCTFail("Expected output to be a string")
        }
    }
}
