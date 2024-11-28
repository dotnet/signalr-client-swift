import Foundation
import XCTest
@testable import SignalRClient

class MockConnection: ConnectionProtocol, @unchecked Sendable {
    var onReceive: Transport.OnReceiveHandler?
    var onClose: Transport.OnCloseHander?
    var onSend: ((StringOrData) -> Void)?

    private(set) var startCalled = false
    private(set) var sendCalled = false
    private(set) var stopCalled = false
    private(set) var sentData: StringOrData?

    func start(transferFormat: TransferFormat) async throws {
        startCalled = true
    }

    func send(_ data: StringOrData) async throws {
        sendCalled = true
        sentData = data
        onSend?(data)
    }

    func stop(error: Error?) async {
        stopCalled = true
    }

    func onReceive(_ handler: @escaping @Sendable (SignalRClient.StringOrData) async -> Void) async {
        onReceive = handler
    }

    func onClose(_ handler: @escaping @Sendable ((any Error)?) async -> Void) async {
        onClose = handler
    }
}

final class HubConnectionTests: XCTestCase {
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
        let handshakeResponse = """
        {}\u{1e}
        """
        await hubConnection.processIncomingData(.string(handshakeResponse))

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
        let handshakeResponse = """
        {"error": "Sample error"}\u{1e}
        """
        await hubConnection.processIncomingData(.string(handshakeResponse))

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
        
        // Response a handshake response
        let handshakeResponse = """
        {}\u{1e}
        """

        // Close connection first
        await mockConnection.onClose?(nil)
        await hubConnection.processIncomingData(.string(handshakeResponse))

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

        XCTAssertEqual(SignalRError.invalidOperation("Start client while not in a disconnected state."), err as? SignalRError)
        // do {
        //     try await hubConnection.start()
        // } catch {
        //     XCTAssertEqual(SignalRError.invalidOperation("Start client while not in a disconnected state."), error as? SignalRError)
        // }
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

