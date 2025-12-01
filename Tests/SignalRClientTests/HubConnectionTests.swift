// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

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
    var features: [ConnectionFeature : Any] = [:]

    private(set) var startCalled = false
    private(set) var sendCalled = false
    private(set) var stopCalled = false
    private(set) var sentData: [StringOrData?] = []

    func start(transferFormat: TransferFormat) async throws {
        startCalled = true
        onStart?()
    }

    func send(_ data: StringOrData) async throws {
        sendCalled = true
        sentData.append(data)
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

    func setFeature(feature: SignalRClient.ConnectionFeature, value: Any) async {
        features[feature] = value
    }

    func resend(callback: @escaping () async -> Any?) async -> Any? {
        if let resendClosure = features[ConnectionFeature.Resend] as? () async -> Any? {
            let _ = await resendClosure()
        }
        return await callback()
    }

    func disconnect(callback: @escaping () async -> Void) async {
        if let disconnectedClosure = features[ConnectionFeature.Disconnected] as? () async -> Void {
            let _ = await disconnectedClosure()
        }
        return await callback()
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
    var hubConnectionForStatefulReconnect: HubConnection!
    var sentCount = 0;
    var sentPingCount = 0;
    var sendExpectation = XCTestExpectation(description: "send() should be called");


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
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
        )
        hubConnectionForStatefulReconnect = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: [0, 1, 2]), 
            serverTimeout: nil,
            keepAliveInterval: 0.5,
            statefulReconnectBufferSize: 10000
        )
    }

    func initForStatefulReconnect() async {
        self.sentCount = 0;
        self.sentPingCount = 0;
        self.sendExpectation = XCTestExpectation(description: "send() should be called");
        let pingExpectation = XCTestExpectation(description: "ping should be called")

        self.mockConnection.onSend = { data in
            do {
                let messages = try self.hubProtocol.parseMessages(input: data, binder: TestInvocationBinder(binderTypes: [Int.self]))
                for message in messages {
                    if message is PingMessage {
                        self.sentPingCount += 1
                        pingExpectation.fulfill()
                        return
                    }
                }
                self.sentCount += 1
                self.sendExpectation.fulfill()
                if (self.sentCount == 1) {
                    Task { await self.hubConnectionForStatefulReconnect.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
                    return
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await self.mockConnection.setFeature(feature: ConnectionFeature.Reconnect, value: true);
        let startTask = Task { try await hubConnectionForStatefulReconnect.start() }
        // defer { startTask.cancel() }

        await whenTaskWithTimeout(startTask, timeout: 1.0)
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Disconnected], "Disconnected feature should be set");
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Resend], "Resend feature should be set");
        await fulfillment(of: [sendExpectation], timeout: 1.0)
        await fulfillment(of: [pingExpectation], timeout: 1.0)
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

        defer { task.cancel() }

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
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
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

        let err = await whenTaskThrowsTimeout(startTask, timeout: 1.0)
        XCTAssertEqual(SignalRError.connectionAborted, err as? SignalRError)
    }

    func testStop_CallsStopDuringConnectAndAfterHandshakeResponse() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: []),
            serverTimeout: nil,
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
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
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
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
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
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

        let reconnectedExpectation = XCTestExpectation(description: "onReconnected() should be called")
        await hubConnection.onReconnected {
            reconnectedExpectation.fulfill()
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
        await fulfillment(of: [reconnectedExpectation], timeout: 1.0)
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
            keepAliveInterval: nil,
            statefulReconnectBufferSize: nil
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
            else {
                return nil;
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
            keepAliveInterval: keepAliveInterval,
            statefulReconnectBufferSize: nil
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

    // Stateful reconnect tests are migrated from https://github.com/dotnet/aspnetcore/blob/v9.0.9/src/SignalR/clients/ts/signalr/tests/HubConnection.test.ts#L1859
    func testStatefulReconnect_sendsSequenceMessageOnReconnect() async throws {
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "reconnect should be called")
        await self.initForStatefulReconnect();

        await mockConnection.disconnect { disconnectExpectation.fulfill() }
        await mockConnection.resend { resendExpectation.fulfill() }

        await fulfillment(of: [disconnectExpectation, resendExpectation], timeout: 0.1)

        // expected 3 sent messages: [{"protocol":"json","version":2}, {"type":6}, {"type":9,"sequenceId":1}], ...(maybe contains more ping messages {"type":6})

        XCTAssertEqual(mockConnection.sentData.count, 2 + sentPingCount);
        let sentHubMessages = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: []))
        XCTAssertEqual(sentHubMessages.count, 1 + sentPingCount);
        XCTAssertTrue(sentHubMessages[0] is PingMessage)
        XCTAssertTrue(sentHubMessages[1] is SequenceMessage)
        XCTAssertEqual((sentHubMessages[1] as! SequenceMessage).sequenceId, 1)
    }

    func testStatefulReconnect_resendsMessagesOnReconnect() async throws {
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "reconnect should be called")
        await self.initForStatefulReconnect()

        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 13) }, timeout: 0.1);
        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 12) }, timeout: 0.1);
        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 11) }, timeout: 0.1);

        await mockConnection.disconnect { disconnectExpectation.fulfill() }
        await mockConnection.resend { resendExpectation.fulfill() }
        await fulfillment(of: [disconnectExpectation], timeout: 1)
        await fulfillment(of: [resendExpectation], timeout: 1)

        /* Expeceted mockConnection.SentData = [
                0 {"protocol":"json","version":2}
                1 {"type":6}
                2 {"target":"test","arguments":[13],"type":1}
                3 {"target":"test","arguments":[12],"type":1}
                4 {"target":"test","arguments":[11],"type":1}
                ... may contains additional ping messages, ignore them
                5 {"type":9,"sequenceId":1}
                6 {"target":"test","arguments":[13],"type":1}
                7 {"target":"test","arguments":[12],"type":1}
                8 {"target":"test","arguments":[11],"type":1}
        ]*/
        // use hubProtocol to parse the messages
        let parsedSentData = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: [Int.self]))
        let sentHubMessage = removeAllPingMessagesButFirst(messages: parsedSentData)
        XCTAssertEqual(sentHubMessage.count, 8) // the first message for handshake is not a HubMessage
        XCTAssertTrue(sentHubMessage[0] is PingMessage)
        XCTAssertTrue(sentHubMessage[4] is SequenceMessage)
        XCTAssertTrue((sentHubMessage[4] as! SequenceMessage).sequenceId == 1)
        XCTAssertTrue(sentHubMessage[5] is InvocationMessage)
        XCTAssertTrue((sentHubMessage[5] as! InvocationMessage).target == "test")
        XCTAssertTrue((sentHubMessage[5] as! InvocationMessage).arguments.value?[0] as? Int == 13)
        XCTAssertTrue(sentHubMessage[6] is InvocationMessage)
        XCTAssertTrue((sentHubMessage[6] as! InvocationMessage).target == "test")
        XCTAssertTrue((sentHubMessage[6] as! InvocationMessage).arguments.value?[0] as? Int == 12)
        XCTAssertTrue(sentHubMessage[7] is InvocationMessage)
        XCTAssertTrue((sentHubMessage[7] as! InvocationMessage).target == "test")
        XCTAssertTrue((sentHubMessage[7] as! InvocationMessage).arguments.value?[0] as? Int == 11)
    }

    func testStatefulReconnect_resendsMessagesWhileDisconnectedOnReconnect() async throws {
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "reconnect should be called")

        await self.initForStatefulReconnect()
    
        // Send first message before disconnect
        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "method1", arguments: 111) }, timeout: 0.1)
    
        // Pretend TestConnection disconnected
        await mockConnection.disconnect { disconnectExpectation.fulfill() }
    
        // Send while disconnected, should wait until resend completes
        let sendDoneExpectation = XCTestExpectation(description: "sendDone should be true")
    
        await mockConnection.resend { resendExpectation.fulfill() }
        let sendTask = Task {
            try await hubConnectionForStatefulReconnect.send(method: "method2", arguments: 222)
            sendDoneExpectation.fulfill()
        }
        await whenTaskWithTimeout(sendTask, timeout: 1)
        await fulfillment(of: [sendDoneExpectation], timeout: 1)
    
        await fulfillment(of: [disconnectExpectation, resendExpectation], timeout: 1)
    
        /* Expected mockConnection.sentData = [
            0 {"protocol":"json","version":2}
            1 {"type":6}  // ping
            2 {"target":"test","arguments":[13],"type":1}  // first send
            3 {"type":9,"sequenceId":1}  // sequence message
            4 {"target":"test","arguments":[13],"type":1}  // resend first message
            5 {"target":"test","arguments":[22],"type":1}  // send message that waited
        ]*/
        
        let parsedSentData = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: [Int.self]))
        let sentHubMessage = removeAllPingMessagesButFirst(messages: parsedSentData)
        
        XCTAssertEqual(sentHubMessage.count, 5)
        XCTAssertTrue(sentHubMessage[0] is PingMessage)

        XCTAssertTrue(sentHubMessage[2] is SequenceMessage)
        XCTAssertEqual((sentHubMessage[2] as! SequenceMessage).sequenceId, 1)

        XCTAssertTrue(sentHubMessage[3] is InvocationMessage)
        XCTAssertEqual((sentHubMessage[3] as! InvocationMessage).target, "method1")
        XCTAssertEqual((sentHubMessage[3] as! InvocationMessage).arguments.value?[0] as? Int, 111)

        XCTAssertTrue(sentHubMessage[4] is InvocationMessage)
        XCTAssertEqual((sentHubMessage[4] as! InvocationMessage).target, "method2")
        XCTAssertEqual((sentHubMessage[4] as! InvocationMessage).arguments.value?[0] as? Int, 222)
    }


    func testStatefulReconnect_receivingAckRemovesBufferedMessages() async throws {
        // Setup stateful reconnect
        await initForStatefulReconnect()

        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 13) }, timeout: 0.1)
        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 14) }, timeout: 0.1)
        await whenTaskWithTimeout(Task { try await hubConnectionForStatefulReconnect.send(method: "test", arguments: 15) }, timeout: 0.1)

        
        let ackMessage = AckMessage(sequenceId: Int64(2))
        let s = try hubProtocol.writeMessage(message: ackMessage)
        await hubConnectionForStatefulReconnect.processIncomingData(s)

        // Simulate disconnect and resend
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "reconnect should be called")

        await mockConnection.disconnect { disconnectExpectation.fulfill() }
        await mockConnection.resend { resendExpectation.fulfill() }
        await fulfillment(of: [disconnectExpectation, resendExpectation], timeout: 1)

        // Now only the last message should be resent, and a new SequenceMessage should be sent
        let parsedSentData = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: [Int.self]))
        let sentHubMessage = removeAllPingMessagesButFirst(messages: parsedSentData)
 
        // {"protocol":"json","version":2}
        // {"type":6}
        // {"target":"test","arguments":[13],"type":1}
        // {"target":"test","arguments":[14],"type":1}
        // {"target":"test","arguments":[15],"type":1}
        // {"type":9,"sequenceId":3}
        // {"target":"test","arguments":[15],"type":1}

        // The last two messages should be SequenceMessage (with sequenceId 3) and InvocationMessage (with argument 15)
        XCTAssertTrue(sentHubMessage[sentHubMessage.count - 2] is SequenceMessage)
        XCTAssertEqual((sentHubMessage[sentHubMessage.count - 2] as! SequenceMessage).sequenceId, 3)
        XCTAssertTrue(sentHubMessage.last is InvocationMessage)
        XCTAssertEqual((sentHubMessage.last as! InvocationMessage).target, "test")
        XCTAssertEqual((sentHubMessage.last as! InvocationMessage).arguments.value?[0] as? Int, 15)
    }

    func testStatefulReconnect_sendsAckAfterReceivingMessage() async throws {
        // Setup stateful reconnect
        await initForStatefulReconnect()
        
        // Send an InvocationMessage to simulate receiving a message from server
        let invocationMessage = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let messageData = try hubProtocol.writeMessage(message: invocationMessage)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData)
        
        // Wait for Ack message to be sent using delayUntil
        try await delayUntil(timeout: 2.0) {
            return self.mockConnection.sentData.count == self.sentPingCount + 2;
        }

        let parsedSentData = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: [Int.self]))
        let messages = removeAllPingMessages(messages: parsedSentData)
        
        XCTAssertNotNil(messages, "Ack message should be sent")
        XCTAssertTrue(messages.last is AckMessage);
        XCTAssertEqual((messages.last as! AckMessage).sequenceId, 1)
    }

    func testStatefulReconnect_sendsAckAfterReceivingManyMessages() async throws {
        // Setup stateful reconnect
        await initForStatefulReconnect()
        
        // Send multiple InvocationMessages to simulate receiving multiple messages from server
        let invocationMessage1 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let invocationMessage2 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let invocationMessage3 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let invocationMessage4 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        
        let messageData1 = try hubProtocol.writeMessage(message: invocationMessage1)
        let messageData2 = try hubProtocol.writeMessage(message: invocationMessage2)
        let messageData3 = try hubProtocol.writeMessage(message: invocationMessage3)
        let messageData4 = try hubProtocol.writeMessage(message: invocationMessage4)
        
        await hubConnectionForStatefulReconnect.processIncomingData(messageData1)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData2)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData3)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData4)
        
        // Wait for Ack message to be sent using delayUntil
        try await delayUntil(timeout: 2.0) {
            // `sentData` contains {"protocol":"json","version":2} and {"type":8,"sequenceId":4} at least.
            return self.mockConnection.sentData.count == self.sentPingCount + 2;
        }

        let parsedSentData = try getParsedData(data: mockConnection.sentData, binder: TestInvocationBinder(binderTypes: [Int.self]))
        let messages = removeAllPingMessages(messages: parsedSentData)

        let ackMessage = messages.last { $0 is AckMessage } as? AckMessage
        XCTAssertNotNil(ackMessage, "Ack message should be sent")
        XCTAssertEqual(ackMessage?.sequenceId, 4)
    }

    func testStatefulReconnect_messagesIgnoredAfterReconnectIfAlreadyReceived() async throws {
        // Setup stateful reconnect
        await initForStatefulReconnect()
        
        var methodCalled = 0
        let methodExpectation = XCTestExpectation(description: "Method should be called")
        methodExpectation.expectedFulfillmentCount = 2
        
        // Register method handler
        await hubConnectionForStatefulReconnect.on(method: "t", types: []) { _ in
            methodCalled += 1
            methodExpectation.fulfill()
        }
        
        // Send two InvocationMessages to simulate receiving messages from server
        let invocationMessage1 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let invocationMessage2 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        
        let messageData1 = try hubProtocol.writeMessage(message: invocationMessage1)
        let messageData2 = try hubProtocol.writeMessage(message: invocationMessage2)
        
        await hubConnectionForStatefulReconnect.processIncomingData(messageData1)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData2)
        
        // Wait for both method calls
        await fulfillment(of: [methodExpectation], timeout: 1.0)
        XCTAssertEqual(methodCalled, 2)
        
        // Verify that HubConnection set the features
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Disconnected], "Disconnected feature should be set")
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Resend], "Resend feature should be set")
        
        // Simulate disconnect and resend
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "resend should be called")
        
        await mockConnection.disconnect { disconnectExpectation.fulfill() }
        await mockConnection.resend { resendExpectation.fulfill() }
        
        await fulfillment(of: [disconnectExpectation, resendExpectation], timeout: 1.0)
        
        // Send Sequence message to indicate we're resuming from sequenceId 1
        let sequenceMessage = SequenceMessage(sequenceId: 1)
        let sequenceData = try hubProtocol.writeMessage(message: sequenceMessage)
        await hubConnectionForStatefulReconnect.processIncomingData(sequenceData)
        
        // Send the same two messages again - they should be ignored
        await hubConnectionForStatefulReconnect.processIncomingData(messageData1)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData2)
        
        // Method should still be called only 2 times (no additional calls)
        XCTAssertEqual(methodCalled, 2)
        
        // Send a new message - this should be processed
        let invocationMessage3 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let messageData3 = try hubProtocol.writeMessage(message: invocationMessage3)
        
        let newMethodExpectation = XCTestExpectation(description: "New method should be called")
        await hubConnectionForStatefulReconnect.on(method: "t", types: []) { _ in
            methodCalled += 1
            newMethodExpectation.fulfill()
        }
        
        await hubConnectionForStatefulReconnect.processIncomingData(messageData3)
        await fulfillment(of: [newMethodExpectation], timeout: 1.0)
        XCTAssertEqual(methodCalled, 3)
    }

    func testStatefulReconnect_messagesIgnoredAfterReconnectIfSequenceMessageNotReceived() async throws {
        // Setup stateful reconnect
        await initForStatefulReconnect()
        
        var methodCalled = 0
        let methodExpectation = XCTestExpectation(description: "Method should be called")
        methodExpectation.expectedFulfillmentCount = 1
        
        // Register method handler
        await hubConnectionForStatefulReconnect.on(method: "t", types: []) { _ in
            methodCalled += 1
            methodExpectation.fulfill()
        }
        
        // Verify that HubConnection set the features
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Disconnected], "Disconnected feature should be set")
        XCTAssertNotNil(mockConnection.features[ConnectionFeature.Resend], "Resend feature should be set")
        
        // Simulate disconnect and resend
        let disconnectExpectation = XCTestExpectation(description: "disconnect should be called")
        let resendExpectation = XCTestExpectation(description: "resend should be called")
        
        await mockConnection.disconnect { disconnectExpectation.fulfill() }
        await mockConnection.resend { resendExpectation.fulfill() }
        
        await fulfillment(of: [disconnectExpectation, resendExpectation], timeout: 1.0)
        
        // Send two InvocationMessages - they should be ignored without sequence message
        let invocationMessage1 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let invocationMessage2 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        
        let messageData1 = try hubProtocol.writeMessage(message: invocationMessage1)
        let messageData2 = try hubProtocol.writeMessage(message: invocationMessage2)
        
        await hubConnectionForStatefulReconnect.processIncomingData(messageData1)
        await hubConnectionForStatefulReconnect.processIncomingData(messageData2)
        
        // Method should not be called yet (messages ignored)
        XCTAssertEqual(methodCalled, 0)
        
        // Send Sequence message to indicate we're resuming from sequenceId 1
        let sequenceMessage = SequenceMessage(sequenceId: 1)
        let sequenceData = try hubProtocol.writeMessage(message: sequenceMessage)
        await hubConnectionForStatefulReconnect.processIncomingData(sequenceData)
        
        // Send a new message - this should be processed
        let invocationMessage3 = InvocationMessage(target: "t", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil)
        let messageData3 = try hubProtocol.writeMessage(message: invocationMessage3)
        
        await hubConnectionForStatefulReconnect.processIncomingData(messageData3)
        await fulfillment(of: [methodExpectation], timeout: 1.0)
        XCTAssertEqual(methodCalled, 1)
    }

    func serverTimeoutTest() async throws {
        hubConnection = HubConnection(
            connection: mockConnection,
            logger: Logger(logLevel: .debug, logHandler: logHandler),
            hubProtocol: hubProtocol,
            retryPolicy: DefaultRetryPolicy(retryDelays: []), // No retry
            serverTimeout: 0.1,
            keepAliveInterval: 99,
            statefulReconnectBufferSize: nil
        )

        let handshakeExpectation = XCTestExpectation(description: "handshake should be called")
        let closeExpectation = XCTestExpectation(description: "close should be called")
        mockConnection.onSend = { data in
            handshakeExpectation.fulfill()
            Task { await self.hubConnection.processIncomingData(.string(self.successHandshakeResponse)) } // only success the first time
        }

        mockConnection.onClose = { error in
            closeExpectation.fulfill()
            XCTAssert(error as! SignalRError == SignalRError.serverTimeout(0.1))
        }

        let startTask = Task { try await hubConnection.start() }
        defer { startTask.cancel() }

        // HubConnect start handshake
        await fulfillment(of: [handshakeExpectation], timeout: 1.0)

        // Response a handshake response
        await whenTaskWithTimeout(startTask, timeout: 1.0)

        // Send keepalive after connect
        await fulfillment(of: [closeExpectation], timeout: 1.0)
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
        let (clientStream, continuation)  = AsyncStream.makeStream(of: Int.self)
       
        let sendTask = Task {
            try await hubConnection.send(method: "testMethod", arguments: "arg1", "arg2", clientStream)
        }

        await fulfillment(of: [sendExpectation], timeout: 1.0)

        // Assert
        await whenTaskWithTimeout(sendTask, timeout: 1.0)
        
        var count = 0
        let streamExpectation = XCTestExpectation(description: "clientStream should trigger send 10 times")
        mockConnection.onSend = { data in
            count += 1
            if count == 10 {
                streamExpectation.fulfill()
            } 
        }

        for i in 0 ..< 9 {
            continuation.yield(i)
        }
        continuation.finish()
        // Assert
        await fulfillment(of: [streamExpectation], timeout: 1.0)
        mockConnection.onSend = nil
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
