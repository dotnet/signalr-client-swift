#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import SignalRClient

final class WebSocketTransportTests: XCTestCase {
    private var webSocketTransport: WebSocketTransport!
    private var mockURLSession: MockURLSession!
    private var mockWebSocketTask: MockWebSocketTask!
    private var accessTokenFactory: (() async throws -> String?)?

    override func setUp() {
        super.setUp()
        mockURLSession = MockURLSession(configuration: .default)
        mockWebSocketTask = MockWebSocketTask()
        accessTokenFactory = { return "mockAccessToken" }
        webSocketTransport = WebSocketTransport(
            accessTokenFactory: accessTokenFactory,
            logger: Logger(logLevel: .debug, logHandler: OSLogHandler()),
            logMessageContent: true,
            headers: ["headerKey": "headerValue"],
            urlSession: mockURLSession
        )
    }

    override func tearDown() {
        webSocketTransport = nil
        mockURLSession = nil
        mockWebSocketTask = nil
        accessTokenFactory = nil
        super.tearDown()
    }

    func testConnect() async throws {
        mockURLSession.mockWebSocketTask = mockWebSocketTask
        try await webSocketTransport.connect(url: "http://example.com", transferFormat: .text)
        
        XCTAssertEqual(mockWebSocketTask.resumeCallCount, 1)
        XCTAssertEqual(mockWebSocketTask.state, .running)
    }

    // func testSendString() async throws {
    //     mockURLSession.mockWebSocketTask = mockWebSocketTask
    //     try await webSocketTransport.connect(url: "http://example.com", transferFormat: .text)
        
    //     try await webSocketTransport.send(.string("testMessage"))
        
    //     XCTAssertEqual(mockWebSocketTask.sentMessages.count, 1)
    //     if case .string(let message) = mockWebSocketTask.sentMessages.first {
    //         XCTAssertEqual(message, "testMessage")
    //     } else {
    //         XCTFail("Expected string message")
    //     }
    // }

    // func testSendData() async throws {
    //     mockURLSession.mockWebSocketTask = mockWebSocketTask
    //     try await webSocketTransport.connect(url: "http://example.com", transferFormat: .text)
        
    //     let testData = "testData".data(using: .utf8)!
    //     try await webSocketTransport.send(.data(testData))
        
    //     XCTAssertEqual(mockWebSocketTask.sentMessages.count, 1)
    //     if case .data(let data) = mockWebSocketTask.sentMessages.first {
    //         XCTAssertEqual(data, testData)
    //     } else {
    //         XCTFail("Expected data message")
    //     }
    // }

    // func testStop() async throws {
    //     mockURLSession.mockWebSocketTask = mockWebSocketTask
    //     try await webSocketTransport.connect(url: "http://example.com", transferFormat: .text)
        
    //     try await webSocketTransport.stop(error: nil)
        
    //     XCTAssertEqual(mockWebSocketTask.cancelCallCount, 1)
    //     XCTAssertEqual(mockURLSession.finishTasksAndInvalidateCallCount, 1)
    // }

    // func testReceiveMessage() async throws {
    //     mockURLSession.mockWebSocketTask = mockWebSocketTask
    //     try await webSocketTransport.connect(url: "http://example.com", transferFormat: .text)
        
    //     let receiveExpectation = expectation(description: "Receive message")
    //     webSocketTransport.onReceive { message in
    //         if case .string(let text) = message {
    //             XCTAssertEqual(text, "testMessage")
    //             receiveExpectation.fulfill()
    //         }
    //     }
        
    //     mockWebSocketTask.mockReceiveMessage = .string("testMessage")
    //     await webSocketTransport.receiveMessage()
        
    //     wait(for: [receiveExpectation], timeout: 1.0)
    // }
}


final class MockURLSession: URLSession, @unchecked Sendable {
    var mockWebSocketTask: MockWebSocketTask?
    var finishTasksAndInvalidateCallCount = 0

    override func webSocketTask(with url: URL) -> URLSessionWebSocketTask {
        return mockWebSocketTask ?? MockWebSocketTask()
    }

    override func finishTasksAndInvalidate() {
        finishTasksAndInvalidateCallCount += 1
    }
}

final class MockWebSocketTask: URLSessionWebSocketTask, @unchecked Sendable {
    var resumeCallCount = 0
    var cancelCallCount = 0
    var sentMessages: [URLSessionWebSocketTask.Message] = []
    var mockReceiveMessage: URLSessionWebSocketTask.Message?

    override func resume() {
        resumeCallCount += 1
    }

    override func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelCallCount += 1
    }
}