import XCTest
@testable import SignalRClient

final class HubConnectionOnResultTests: XCTestCase {
    let successHandshakeResponse = """
        {}\u{1e}
    """
    let errorHandshakeResponse = """
        {"error": "Sample error"}\u{1e}
    """
    let resultValue = 42

    var mockConnection: MockConnection!
    var logHandler: LogHandler!
    var hubProtocol: HubProtocol!
    var hubConnection: HubConnection!

    var resultExpectation: XCTestExpectation = XCTestExpectation(description: "Result received")
    var result: CompletionMessage?

    override func setUp() async throws {
        mockConnection = MockConnection()
        logHandler = MockLogHandler()
        hubProtocol = JsonHubProtocol()
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: []), // No retry
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        mockConnection.onSend = { data in
            Task { 
                guard let hubConnection = self.hubConnection else { return }
                let messages = try self.hubProtocol.parseMessages(input: data, binder: TestInvocationBinder(binderTypes: [Int.self]))
                if messages.first is CompletionMessage {
                    self.resultExpectation.fulfill()
                    self.result = (messages.first as! CompletionMessage)
                } else {
                    await hubConnection.processIncomingData(.string(self.successHandshakeResponse)) 
                }
            } // only success the first time
        }

        try await hubConnection.start()
    }

    override func tearDown() {
        hubConnection = nil
        super.tearDown()
    }

    func testOnNoArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") {
            expectation.fulfill()
            return self.resultValue
        }

        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: "invocationId"))
        await fulfillment(of: [expectation, resultExpectation], timeout: 1)
        XCTAssertEqual(result?.result.value as? Int, self.resultValue)
    }

    func testOnNoArgs_VoidReturn() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") {
            expectation.fulfill()
            return
        }

        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: "invocationId"))
        await fulfillment(of: [expectation, resultExpectation], timeout: 1)
        XCTAssertNil(result?.result.value)
    }

    func testOnAndOff() async throws {
        let expectation = self.expectation(description: "Handler called")
        expectation.isInverted = true
        await hubConnection.on("testMethod") {
            expectation.fulfill()
            return self.resultValue
        }
        await hubConnection.off(method: "testMethod")

        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: "invocationId"))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnOneArg() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg: Int) in
            XCTAssertEqual(arg, 42)
            expectation.fulfill()
            return self.resultValue
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42]), streamIds: nil, headers: nil, invocationId: "invocationId"))
        await fulfillment(of: [expectation, resultExpectation], timeout: 1)
        XCTAssertEqual(result?.result.value as? Int, self.resultValue)
    }

    func testOnOneArg_WrongType() async throws {
        let expectation = self.expectation(description: "Handler called")
        expectation.isInverted = true
        await hubConnection.on("testMethod") { (arg: Int) in
            XCTAssertEqual(arg, 42)
            expectation.fulfill()
            return self.resultValue
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray(["42"]), streamIds: nil, headers: nil, invocationId: "invocationId"))

        await fulfillment(of: [expectation], timeout: 1)
    }
}