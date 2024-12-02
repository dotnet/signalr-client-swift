import Foundation
import XCTest
@testable import SignalRClient

class MockConnection: ConnectionProtocol, @unchecked Sendable {
    var onReceive: Transport.OnReceiveHandler?
    var onClose: Transport.OnCloseHander?
    var onSend: ((StringOrData) -> Void)?
    var onStart: (() -> Void)?

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
        await onClose?(error)
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
            retryPolicy: DefaultRetryPolicy(retryDelays: [1, 2, 3]), // Add some retry, but in this case, it shouldn't have effect
            serverTimeout: nil,
            keepAliveInterval: nil
        )

        let sendExpectation = XCTestExpectation(description: "send() should be called")
        let closeEcpectation = XCTestExpectation(description: "close() should be called")
        mockConnection.onSend = { data in
            sendExpectation.fulfill()
        }

        mockConnection.onClose = { error in
            closeEcpectation.fulfill()
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
            await fulfillment(of: [closeEcpectation], timeout: 1.0)
        } catch {
            XCTAssertEqual(SignalRError.connectionAborted, error as? SignalRError)
        }
    }

    func testReconnect() async throws {
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
        // await hubConnection.processIncomingData(.string(successHandshakeResponse))
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

    func whenTaskWithTimeout(_ task: Task<Void, Error>, timeout: TimeInterval) async -> Void {
        return await whenTaskWithTimeout({ try await task.value }, timeout: timeout)
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
