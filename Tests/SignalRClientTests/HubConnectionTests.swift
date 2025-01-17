import Foundation
import XCTest
@testable import SignalRClient

class MockConnection: ConnectionProtocol, @unchecked Sendable {
    var inherentKeepAlive: Bool = false

    var onReceive: Transport.OnReceiveHandler?
    var onClose: Transport.OnCloseHander?
    var onSend: ((StringOrData) -> Void)?
    var onStart: (() -> Void)?
    var onStop: ((Error?) -> Void)?

    private(set) var startCalled = false
    private(set) var sendCalled = false
    private(set) var stopCalled = false
    private(set) var sentData: StringOrData?

    func start(transferFormat: TransferFormat) async throws {
        startCalled = true
        onStart?()
    }

    func send(_ data: StringOrData) async throws {
        sendCalled = true
        sentData = data
        onSend?(data)
    }

    func stop(error: Error?) async {
        stopCalled = true
        onStop?(error)
    }

    func onReceive(_ handler: @escaping @Sendable (SignalRClient.StringOrData) async -> Void) async {
        onReceive = handler
    }

    func onClose(_ handler: @escaping @Sendable ((any Error)?) async -> Void) async {
        onClose = handler
    }
}

final class HubConnectionTests: XCTestCase {
    let successHandshakeResponse = """
        {}\u{1e}
    """
    let errorHandshakeResponse = """
        {"error": "Sample error"}\u{1e}
    """

    var mockConnection: MockConnection!
    var logHandler: LogHandler!
    var hubProtocol: HubProtocol!
    var hubConnection: HubConnection!

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
    }

    func testStart_CallsStartOnConnection() async throws {
        // Act
        let expectation = XCTestExpectation(description: "send() should be called")

        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0) 
        // Assert
        let state = await hubConnection.state()
        XCTAssertEqual(HubConnectionState.Connected, state)
    }

    func testStart_FailedHandshake() async throws {
        // Act
        let expectation = XCTestExpectation(description: "send() should be called")

        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(errorHandshakeResponse))

        _ = await whenTaskThrowsTimeout({ try await task.value }, timeout: 1.0) 
        // Assert
        let state = await hubConnection.state()
        XCTAssertEqual(HubConnectionState.Stopped, state)
    }

    func testStart_ConnectionCloseRightAfterHandshake() async throws {
        // Act
        let expectation = XCTestExpectation(description: "send() should be called")

        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Close connection first
        await mockConnection.onClose?(nil)
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        let err = await whenTaskThrowsTimeout({ try await task.value }, timeout: 1.0)

        // Assert
        XCTAssertEqual(SignalRError.connectionAborted, err as? SignalRError)
        let state = await hubConnection.state()
        XCTAssertEqual(HubConnectionState.Stopped, state)
    }

    func testStart_DuplicateStart() async throws {
        // Act
        let expectation = XCTestExpectation(description: "send() should be called")

        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        defer {task.cancel()}
        
        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)


        let err = await whenTaskThrowsTimeout({
            try await self.hubConnection.start()
        }, timeout: 1.0)

        XCTAssertEqual(SignalRError.invalidOperation("Start client while not in a stopped state."), err as? SignalRError)
    }


    func testStop_CallsStopDuringConnect() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: [1, 2, 3]), // Add some retry, but in this case, it shouldn't have effect
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let expectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)

        // The moment start is waiting for handshake response but it should throw 
        await hubConnection.stop()

        let err =  await whenTaskThrowsTimeout(startTask, timeout: 1.0)
        XCTAssertEqual(SignalRError.connectionAborted, err as? SignalRError)
    }

    func testStop_CallsStopDuringConnectAndAfterHandshakeResponse() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: []),
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let sendExpectation = XCTestExpectation(description: "send() should be called")
        let closeExpectation = XCTestExpectation(description: "close() should be called")
        mockConnection.onSend = { data in
            sendExpectation.fulfill()
        }

        mockConnection.onStop = { error in
            closeExpectation.fulfill()
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))
        await hubConnection.stop()

        // Two possible
        // 1. startTask throws
        // 2. connection.stop called
        do {
            try await startTask.value
            await fulfillment(of: [closeExpectation], timeout: 1.0)    
        } catch {
            XCTAssertEqual(SignalRError.connectionAborted, error as? SignalRError)
        }
    }

    func testReconnect_ExceedRetry() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: [0.1, 0.2, 0.3]), // Add some retry
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let sendExpectation = XCTestExpectation(description: "send() should be called")
        let openExpectations = [
            XCTestExpectation(description: "onOpen should be called 1"),
            XCTestExpectation(description: "onOpen should be called 2"),
            XCTestExpectation(description: "onOpen should be called 3"),
            XCTestExpectation(description: "onOpen should be called 4"),
        ]
        let closeEcpectation = XCTestExpectation(description: "close() should be called")
        var sendCount = 0
        mockConnection.onSend = { data in
            if (sendCount == 0) {
                sendCount += 1
                Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
            } else {
                Task { await self.hubConnection.processIncomingData(.string(self.errorHandshakeResponse)) } // for reconnect, it always fails
            }
            
            sendExpectation.fulfill()
        }

        var openCount = 0
        mockConnection.onStart = {
            openCount += 1
            if (openCount <= 4) {
                openExpectations[openCount - 1].fulfill()
            }
        }

        mockConnection.onClose = { error in
            closeEcpectation.fulfill()
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Response a handshake response
        await whenTaskWithTimeout(startTask, timeout: 1.0)

        // Simulate connection close
        let handleCloseTask = Task { await hubConnection.handleConnectionClose(error: nil) }

        // retry will work and start will be called again
        await fulfillment(of: [openExpectations[1]], timeout: 1.0)

        await fulfillment(of: [openExpectations[2]], timeout: 1.0)

        await fulfillment(of: [openExpectations[3]], timeout: 1.0)

        // Retry failed
        await handleCloseTask.value
        let state = await hubConnection.state()
        XCTAssertEqual(state, HubConnectionState.Stopped)
    }

    func testReconnect_Success() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: [0.1, 0.2]), // Limited retries
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let sendExpectation = XCTestExpectation(description: "send() should be called")
        let openExpectations = [
            XCTestExpectation(description: "onOpen should be called 1"),
            XCTestExpectation(description: "onOpen should be called 2"),
            XCTestExpectation(description: "onOpen should be called 3"),
        ]
        var sendCount = 0
        mockConnection.onSend = { data in
            if (sendCount == 0) {
                Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
            } else if (sendCount == 1) {
                Task { await self.hubConnection.processIncomingData(.string(self.errorHandshakeResponse)) } // for the first reconnect, it fails
            } else {
                Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // for the second reconnect, it success
            }
            sendCount += 1
            sendExpectation.fulfill()
        }

        var openCount = 0
        mockConnection.onStart = {
            openCount += 1
            if (openCount <= 3) {
                openExpectations[openCount - 1].fulfill()
            }
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Response a handshake response
        await whenTaskWithTimeout(startTask, timeout: 1.0)

        // Simulate connection close
        let handleCloseTask = Task { await hubConnection.handleConnectionClose(error: nil) }

        // retry will work and start will be called again
        await fulfillment(of: [openExpectations[1]], timeout: 1.0)

        await fulfillment(of: [openExpectations[2]], timeout: 1.0)

        // Retry success
        await handleCloseTask.value
        let state = await hubConnection.state()
        XCTAssertEqual(state, HubConnectionState.Connected)
    }

    func testReconnect_CustomPolicy() async throws {
        class CustomRetryPolicy: RetryPolicy, @unchecked Sendable {
            func nextRetryInterval(retryContext: SignalRClient.RetryContext) -> TimeInterval? {
                return onRetry?(retryContext)
            }

            var onRetry: ((RetryContext) -> TimeInterval?)?
        }

        class CustomError: Error, @unchecked Sendable {}
        let retryPolicy = CustomRetryPolicy()

        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: retryPolicy, // Limited retries
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let sendExpectation = XCTestExpectation(description: "send() should be called")
        var sendCount = 0
        mockConnection.onSend = { data in
            if (sendCount == 0) {
                Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
            } else {
                Task { await self.hubConnection.processIncomingData(.string(self.errorHandshakeResponse)) } // for the first reconnect, it fails
            }
            sendCount += 1
            sendExpectation.fulfill()
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Response a handshake response
        await whenTaskWithTimeout(startTask, timeout: 1.0)

        let retryExpectations = [
            XCTestExpectation(description: "retry should be called 1"),
            XCTestExpectation(description: "retry should be called 2"),
            XCTestExpectation(description: "retry should be called 3"),
        ]
        var retryCount = 0
        var previousElaped: TimeInterval = 0
        retryPolicy.onRetry = { retryContext in
            if (retryCount == 0) {
                XCTAssert(retryContext.retryReason is CustomError)
                XCTAssertEqual(retryContext.elapsed, 0)
                XCTAssertEqual(retryContext.retryCount, 0)
            } else {
                XCTAssertEqual(retryContext.retryCount, retryCount)
                XCTAssert(previousElaped < retryContext.elapsed)
                XCTAssert(retryContext.retryReason is SignalRError)
            }
            if (retryCount < 3) {
                retryExpectations[retryCount].fulfill()
            }
            retryCount += 1
            previousElaped = retryContext.elapsed
            return 0.1
        }

        let reconnectingExpectations = [
            XCTestExpectation(description: "reconnecting should be called 1"),
            XCTestExpectation(description: "reconnecting should be called 2"),
            XCTestExpectation(description: "reconnecting should be called 3"),
        ]
        var reconnectingCount = 0
        await hubConnection.onReconnecting { error in
            if (reconnectingCount < 3) {
                reconnectingExpectations[reconnectingCount].fulfill()
            }
            reconnectingCount += 1
        }

        // Simulate connection close
        let handleCloseTask = Task { await hubConnection.handleConnectionClose(error: CustomError()) }

        // retry will work and start will be called again
        await fulfillment(of: [retryExpectations[0]], timeout: 1.0)
        await fulfillment(of: [reconnectingExpectations[0]], timeout: 1.0)
        await fulfillment(of: [retryExpectations[1]], timeout: 1.0)
        await fulfillment(of: [reconnectingExpectations[1]], timeout: 1.0)
        await fulfillment(of: [retryExpectations[2]], timeout: 1.0)
        await fulfillment(of: [reconnectingExpectations[2]], timeout: 1.0)

        await hubConnection.stop()

        // Retry success
        await handleCloseTask.value
        let state = await hubConnection.state()
        XCTAssertEqual(state, HubConnectionState.Stopped)
    }

    func testKeepAlive() async throws {
        let keepAliveInterval: TimeInterval = 0.1
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: []), // No retry
            serverTimeout: nil,
            keepAliveInterval: keepAliveInterval
        )

        let handshakeExpectation = XCTestExpectation(description: "handshake should be called")
        let pingExpectations = [
            XCTestExpectation(description: "ping should be called"),
            XCTestExpectation(description: "ping should be called"),
            XCTestExpectation(description: "ping should be called")
        ]
        var sendCount = 0
        mockConnection.onSend = { data in
            do {
                let messages = try self.hubProtocol.parseMessages(input: data, binder: TestInvocationBinder(binderTypes: []))
                for message in messages {
                    if let pingMessage = message as? PingMessage {
                        if sendCount < pingExpectations.count {
                            pingExpectations[sendCount].fulfill()
                        }
                        sendCount += 1
                        return
                    }
                }
                handshakeExpectation.fulfill()
                Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [handshakeExpectation], timeout: 1.0)

        // Response a handshake response
        await whenTaskWithTimeout(startTask, timeout: 1.0)

        // Send keepalive after connect
        await fulfillment(of: [pingExpectations[0], pingExpectations[1], pingExpectations[2]], timeout: 1.0)
    }

    func testSend() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let sendExpectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            sendExpectation.fulfill()
        }

        let sendTask = Task {
            try await hubConnection.send(method: "testMethod", arguments: "arg1", "arg2")
        }

        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Assert
        await whenTaskWithTimeout(sendTask, timeout: 1.0)
    }

    func testInvoke_Success() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        let expectedResult = "result"
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "invoke() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            let result: String = try await hubConnection.invoke(method: "testMethod", arguments: "arg1", "arg2")
            XCTAssertEqual(result, expectedResult)
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        // Simulate server response
        let invocationId = "1"
        let completionMessage = CompletionMessage(invocationId: invocationId, error: nil, result: AnyEncodable(expectedResult), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: completionMessage))

        // Assert
        await whenTaskWithTimeout(invokeTask, timeout: 1.0)
    }

    func testInvoke_Success_Void() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "invoke() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            try await hubConnection.invoke(method: "testMethod", arguments: "arg1", "arg2")
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        // Simulate server response
        let invocationId = "1"
        let completionMessage = CompletionMessage(invocationId: invocationId, error: nil, result: AnyEncodable(nil), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: completionMessage))

        // Assert
        await whenTaskWithTimeout(invokeTask, timeout: 1.0)
    }

    func testInvokeWithWrongReturnType() async throws {
        let expectation = XCTestExpectation(description: "send() should be called")
        let expectedResult = "result"
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "invoke() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            let s: Int = try await self.hubConnection.invoke(method: "testMethod", arguments: "arg1", "arg2")
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        // Simulate server response
        let invocationId = "1"
        let completionMessage = CompletionMessage(invocationId: invocationId, error: nil, result: AnyEncodable(expectedResult), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: completionMessage))

        // Assert
        let error = await whenTaskThrowsTimeout(invokeTask, timeout: 1.0)
        XCTAssertEqual(error as? SignalRError, SignalRError.invalidOperation("Cannot convert the result of the invocation to the specified type."))
    }

    func testInvoke_Failure() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        let expectedError = SignalRError.invocationError("Sample error")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "invoke() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            do {
                let _: String = try await hubConnection.invoke(method: "testMethod", arguments: "arg1", "arg2")
                XCTFail("Expected error not thrown")
            } catch {
                XCTAssertEqual(error as? SignalRError, expectedError)
            }
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)
        // Simulate server response
        let invocationId = "1"
        let completionMessage = CompletionMessage(invocationId: invocationId, error: "Sample error", result: AnyEncodable(nil), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: completionMessage))

        // Assert
        await whenTaskWithTimeout(invokeTask, timeout: 1.0)
    }

    func testStream_Success() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        let expectedResults = ["result1", "result2", "result3", "result4"]
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "stream() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            let stream: any StreamResult<String> = try await hubConnection.stream(method: "testMethod", arguments: "arg1", "arg2")
            var i = 0
            for try await element in stream.stream {
                XCTAssertEqual(element, expectedResults[i])
                i += 1
            }
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        // Simulate server stream back
        let invocationId = "1"
        let streamItemMessage1 = StreamItemMessage(invocationId: invocationId, item: AnyEncodable("result1"), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: streamItemMessage1))
        let streamItemMessage2 = StreamItemMessage(invocationId: invocationId, item: AnyEncodable("result2"), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: streamItemMessage2))
        let streamItemMessage3 = StreamItemMessage(invocationId: invocationId, item: AnyEncodable("result3"), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: streamItemMessage3))
        let completionMessage = CompletionMessage(invocationId: invocationId, error: nil, result: AnyEncodable("result4"), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: completionMessage))

        // Assert
        await whenTaskWithTimeout(invokeTask, timeout: 1.0)
    }

    func testStream_Failed_WrongType() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "stream() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let invokeTask = Task {
            let stream: any StreamResult<String> = try await hubConnection.stream(method: "testMethod", arguments: "arg1", "arg2")
            for try await _ in stream.stream {
            }
        }

        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        // Simulate server stream back
        let invocationId = "1"
        let streamItemMessage1 = StreamItemMessage(invocationId: invocationId, item: AnyEncodable(123), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: streamItemMessage1))
        
        // Assert
        let error = await whenTaskThrowsTimeout(invokeTask, timeout: 1.0)
        XCTAssertEqual(error as? SignalRError, SignalRError.invalidOperation("Cannot convert the result of the invocation to the specified type."))
    }

    func testStream_Cancel() async throws {
        // Arrange
        let expectation = XCTestExpectation(description: "send() should be called")
        mockConnection.onSend = { data in
            expectation.fulfill()
        }

        let task = Task {
            try await hubConnection.start()
        }

        // HubConnect start handshake
        await fulfillment(of: [expectation], timeout: 1.0)
        
        // Response a handshake response
        await hubConnection.processIncomingData(.string(successHandshakeResponse))

        await whenTaskWithTimeout({ try await task.value }, timeout: 1.0)

        // Act
        let invokeExpectation = XCTestExpectation(description: "stream() should be called")
        mockConnection.onSend = { data in
            invokeExpectation.fulfill()
        }

        let stream: any StreamResult<String> = try await hubConnection.stream(method: "testMethod", arguments: "arg1", "arg2")
        await fulfillment(of: [invokeExpectation], timeout: 1.0)

        let cancelExpectation = XCTestExpectation(description: "send() should be called to send cancel")
        mockConnection.onSend = { data in
            cancelExpectation.fulfill()
        }

        await stream.cancel()
        await fulfillment(of: [cancelExpectation], timeout: 1.0)

        // After cancel, more data to the stream should be ignored
        let invocationId = "1"
        let streamItemMessage1 = StreamItemMessage(invocationId: invocationId, item: AnyEncodable(123), headers: nil)
        await hubConnection.processIncomingData(try hubProtocol.writeMessage(message: streamItemMessage1))
    }

    func whenTaskWithTimeout(_ task: Task<Void, Error>, timeout: TimeInterval) async -> Void {
        return await whenTaskWithTimeout({ try await task.value }, timeout: timeout)
    }

    func whenTaskWithTimeout(_ task: Task<Void, Never>, timeout: TimeInterval) async -> Void {
        return await whenTaskWithTimeout({ await task.value }, timeout: timeout)
    }

    func whenTaskWithTimeout(_ task: @escaping () async throws -> Void, timeout: TimeInterval) async -> Void {
        let expectation = XCTestExpectation(description: "Task should complete")
        let wrappedTask = Task {
            _ = try await task()
            expectation.fulfill()
        }
        defer { wrappedTask.cancel() }

        await fulfillment(of: [expectation], timeout: timeout)
    }

    func whenTaskThrowsTimeout(_ task: Task<Void, Error>, timeout: TimeInterval) async -> Error? {
        return await whenTaskThrowsTimeout({ try await task.value }, timeout: timeout)
    }

    func whenTaskThrowsTimeout(_ task: @escaping () async throws -> Void, timeout: TimeInterval) async -> Error? {
        let returnErr: ValueContainer<Error> = ValueContainer()
        let expectation = XCTestExpectation(description: "Task should throw")
        let wrappedTask = Task {
            do {
                _ = try await task()
            } catch {
                await returnErr.update(error)
                expectation.fulfill()
            }
        }
        defer { wrappedTask.cancel() }

        await fulfillment(of: [expectation], timeout: timeout)

        return await returnErr.get()
    }

    private actor ValueContainer<T> {
        private var value: T?

        func update(_ newValue: T?) {
            value = newValue
        }

        func get() -> T? {
            return value
        }
    }
}

