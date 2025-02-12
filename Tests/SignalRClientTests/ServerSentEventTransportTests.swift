#if canImport(EventSource)
import XCTest

@testable import SignalRClient

actor MockEventSourceAdaptor: EventSourceAdaptor{
    let canConnect: Bool
    let sendMessage: Bool
    let disconnect: Bool
    
    var messageHandler: ((String) async -> Void)?
    var closeHandler: (((any Error)?) async -> Void)?

    init(canConnect: Bool, sendMessage: Bool, disconnect: Bool){
        self.canConnect = canConnect
        self.sendMessage = sendMessage
        self.disconnect = disconnect
    }
    
    func start(url: String, headers: [String : String]) async throws {
        guard self.canConnect else {
            throw SignalRError.eventSourceFailedToConnect
        }
        Task{
            try await Task.sleep(for: .milliseconds(100))
            if sendMessage {
                await self.messageHandler?("123")
            }
            try await Task.sleep(for: .milliseconds(200))
            if disconnect {
                await self.closeHandler?(SignalRError.connectionAborted)
            }
        }
    }
    
    func stop(err: Error?) async {
        await self.closeHandler?(err)
    }
    
    func onClose(closeHandler: @escaping ((any Error)?) async -> Void) async {
        self.closeHandler = closeHandler
    }
    
    func onMessage(messageHandler: @escaping (String) async -> Void) async {
        self.messageHandler = messageHandler

    }
}

class ServerSentEventTransportTests: XCTestCase {
    // MARK: connect
    func testConnectSucceed() async throws{
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        let eventSource = MockEventSourceAdaptor(canConnect: true, sendMessage: false, disconnect: false)
        options.eventSource = eventSource
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        try await sse.connect(url: "https://www.bing.com/signalr", transferFormat: .text)
        logHandler.verifyLogged("Connecting")
        logHandler.verifyLogged("connected")
    }
    
    func testConnectWrongTranferformat() async throws{
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        let eventSource = MockEventSourceAdaptor(canConnect: true, sendMessage: false, disconnect: false)
        options.eventSource = eventSource
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        await sse.SetEventSource(eventSource: eventSource)
        do{
            try await sse.connect(url: "https://abc", transferFormat: .binary)
            XCTFail("SSE connect should fail")
        }catch SignalRError.eventSourceInvalidTransferFormat {
        }
        logHandler.verifyNotLogged("connected")
    }
    
    func testConnectFail() async throws{
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        let eventSource = MockEventSourceAdaptor(canConnect: false, sendMessage: false, disconnect: false)
        options.eventSource = eventSource
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        do{
            try await sse.connect(url: "https://abc", transferFormat: .text)
            XCTFail("SSE connect should fail")
        }catch SignalRError.eventSourceFailedToConnect {
        }
        logHandler.verifyNotLogged("connected")
    }
    
    func testConnectAndReceiveMessage() async throws{
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        let eventSource = MockEventSourceAdaptor(canConnect: true, sendMessage: true, disconnect: false)
        options.eventSource = eventSource
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        let expectation = XCTestExpectation(description: "Message should be received")
        await sse.onReceive(){ message in
            switch message{
            case .string(let str):
                if str == "123"{
                    expectation.fulfill()
                }
            default:
                break
            }
        }
        try await sse.connect(url: "https://abc", transferFormat: .text)
        logHandler.verifyLogged("connected")
        await fulfillment(of: [expectation], timeout: 1)
    }
    
    func testConnectAndDisconnect() async throws{
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        let eventSource = MockEventSourceAdaptor(canConnect: true, sendMessage: false, disconnect: true)
        options.eventSource = eventSource
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        let expectation = XCTestExpectation(description: "SSE should be disconnected")
        await sse.onClose(){ err in
            let err = err as? SignalRError
            if err == SignalRError.connectionAborted {
                expectation.fulfill()
            }
        }
        try await sse.connect(url: "https://abc", transferFormat: .text)
        logHandler.verifyLogged("connected")
        await fulfillment(of: [expectation], timeout: 1)
    }
    
    // MARK: send
    func testSend() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        let options = HttpConnectionOptions()
        let sse = ServerSentEventTransport(
            httpClient: client,accessToken: "", logger: logger, options: options)
        let eventSource = MockEventSourceAdaptor(canConnect: false, sendMessage: false, disconnect: false)
        await sse.SetEventSource(eventSource: eventSource)
        await sse.SetUrl(url: "http://abc")
        await client.mock(mockId: "string") { request in
            XCTAssertEqual(request.content, StringOrData.string("stringbody"))
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 200)
            )
        }
        await sse.SetMockId(mockId: "string")
        try await sse.send(.string("stringbody"))
        logHandler.verifyLogged("200")
    }
    
    // MARK: asyncStream
    func testAsyncStream() async {
        let stream: AsyncStream<Int> = AsyncStream{ continuition in
            Task{
                for i in 0...99{
                    try await Task.sleep(for: .microseconds(100))
                    continuition.yield(i)
                }
                continuition.finish()
            }
        }
        var count = 0
        for await _ in stream{
            count += 1
        }
        XCTAssertEqual(count, 100)
    }
}

extension ServerSentEventTransport {
    fileprivate func SetEventSource(eventSource: EventSourceAdaptor) {
        self.eventSource = eventSource
    }

    fileprivate func SetUrl(url: String) {
        self.url = url
    }

    fileprivate func SetMockId(mockId: String) {
        if self.options.headers == nil {
            self.options.headers = [:]
        }
        self.options.headers![mockKey] = mockId
    }
}
#endif