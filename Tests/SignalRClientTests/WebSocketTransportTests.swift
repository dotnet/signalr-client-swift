#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import XCTest
@testable import SignalRClient

class WebSocketTransportTests: XCTestCase {
    private var logger: Logger!
    private var mockWebSocketConnection: MockWebSocketConnection!
    private var webSocketTransport: WebSocketTransport!

    override func setUp() {
        super.setUp()
        logger = Logger(logLevel: .debug, logHandler: DefaultLogHandler())
        mockWebSocketConnection = MockWebSocketConnection()
        webSocketTransport = WebSocketTransport(accessTokenFactory: nil, logger: logger, headers: [:], websocket: mockWebSocketConnection)
    }

    func testConnect() async throws {
        let url = "http://example.com"
        try await webSocketTransport.connect(url: url, transferFormat: .text)
        XCTAssertTrue(mockWebSocketConnection.connectCalled)
    }

    func testSend() async throws {
        let data = StringOrData.string("test message")
        try await webSocketTransport.send(data)
        XCTAssertEqual(mockWebSocketConnection.sentData, data)
    }

    func testStop() async throws {
        try await webSocketTransport.stop(error: nil)
        XCTAssertTrue(mockWebSocketConnection.stopCalled)
    }

    func testOnReceive() async {
        let expectation = XCTestExpectation(description: "onReceive handler called")
        await webSocketTransport.onReceive { data in
            expectation.fulfill()
        }
        await mockWebSocketConnection.triggerReceive(.string("test message"))
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testOnClose() async {
        let expectation = XCTestExpectation(description: "onClose handler called")
        await webSocketTransport.onClose { error in
            expectation.fulfill()
        }
        await mockWebSocketConnection.triggerClose(nil)
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testConnectWithHttpUrl() async throws {
        let url = "http://example.com"
        try await webSocketTransport.connect(url: url, transferFormat: .text)
        XCTAssertTrue(mockWebSocketConnection.connectCalled)
        XCTAssertEqual(mockWebSocketConnection.request?.url?.scheme, "ws")
    }

    func testConnectWithHttpsUrl() async throws {
        let url = "https://example.com"
        try await webSocketTransport.connect(url: url, transferFormat: .text)
        XCTAssertTrue(mockWebSocketConnection.connectCalled)
        XCTAssertEqual(mockWebSocketConnection.request?.url?.scheme, "wss")
    }

    func testConnectWithHeaders() async throws {
        let headers = ["Authorization": "Bearer token"]
        webSocketTransport = WebSocketTransport(accessTokenFactory: nil, logger: logger, headers: headers, websocket: mockWebSocketConnection)
        let url = "http://example.com"
        try await webSocketTransport.connect(url: url, transferFormat: .text)
        XCTAssertTrue(mockWebSocketConnection.connectCalled)
        XCTAssertEqual(mockWebSocketConnection.request?.allHTTPHeaderFields?["Authorization"], "Bearer token")
    }

    func testConnectWithAccessToken() async throws {
        let accessTokenFactory: @Sendable () async throws -> String? = { return "test_token" }
        webSocketTransport = WebSocketTransport(accessTokenFactory: accessTokenFactory, logger: logger, headers: [:], websocket: mockWebSocketConnection)
        let url = "http://example.com"
        try await webSocketTransport.connect(url: url, transferFormat: .text)
        XCTAssertTrue(mockWebSocketConnection.connectCalled)
        XCTAssertEqual(mockWebSocketConnection.request?.url?.query, "access_token=test_token")
    }
}

class MockWebSocketConnection: WebSocketTransport.WebSocketConnection {
    var connectCalled = false
    var sentData: StringOrData?
    var stopCalled = false
    var onReceiveHandler: Transport.OnReceiveHandler?
    var onCloseHandler: Transport.OnCloseHander?
    var request: URLRequest?

    func connect(request: URLRequest, transferFormat: TransferFormat) async throws {
        self.request = request
        connectCalled = true
    }

    func send(_ data: StringOrData) async throws {
        sentData = data
    }

    func stop(error: Error?) async {
        stopCalled = true
    }

    func onReceive(_ handler: Transport.OnReceiveHandler?) async {
        onReceiveHandler = handler
    }

    func onClose(_ handler: Transport.OnCloseHander?) async {
        onCloseHandler = handler
    }

    func triggerReceive(_ data: StringOrData) async {
        await onReceiveHandler?(data)
    }

    func triggerClose(_ error: Error?) async {
        await onCloseHandler?(error)
    }
}
