// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest
@testable import SignalRClient

final class HubConnectionOnTests: XCTestCase {
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

        mockConnection.onSend = { data in
            Task { 
                guard let hubConnection = self.hubConnection else { return }
                await hubConnection.processIncomingData(.string(self.successHandshakeResponse)) 
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
        }

        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnAndOff() async throws {
        let expectation = self.expectation(description: "Handler called")
        expectation.isInverted = true
        await hubConnection.on("testMethod") {
            expectation.fulfill()
        }
        await hubConnection.off(method: "testMethod")

        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnOneArg() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg: Int) in
            XCTAssertEqual(arg, 42)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnOneArg_WrongType() async throws {
        let expectation = self.expectation(description: "Handler called")
        expectation.isInverted = true
        await hubConnection.on("testMethod") { (arg: Int) in
            XCTAssertEqual(arg, 42)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray(["42"]), streamIds: nil, headers: nil, invocationId: nil))

        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnTwoArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test"]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnThreeArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnFourArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnFiveArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double, arg5: Double) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            XCTAssertEqual(arg5, 2.71)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14, 2.71]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnSixArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double, arg5: Double, arg6: Int) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            XCTAssertEqual(arg5, 2.71)
            XCTAssertEqual(arg6, 99)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14, 2.71, 99]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnSevenArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double, arg5: Double, arg6: Int, arg7: String) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            XCTAssertEqual(arg5, 2.71)
            XCTAssertEqual(arg6, 99)
            XCTAssertEqual(arg7, "end")
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14, 2.71, 99, "end"]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnEightArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double, arg5: Double, arg6: Int, arg7: String, arg8: Bool) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            XCTAssertEqual(arg5, 2.71)
            XCTAssertEqual(arg6, 99)
            XCTAssertEqual(arg7, "end")
            XCTAssertEqual(arg8, false)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14, 2.71, 99, "end", false]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testOnNineArgs() async throws {
        let expectation = self.expectation(description: "Handler called")
        await hubConnection.on("testMethod") { (arg1: Int, arg2: String, arg3: Bool, arg4: Double, arg5: Double, arg6: Int, arg7: String, arg8: Bool, arg9: Int) in
            XCTAssertEqual(arg1, 42)
            XCTAssertEqual(arg2, "test")
            XCTAssertEqual(arg3, true)
            XCTAssertEqual(arg4, 3.14)
            XCTAssertEqual(arg5, 2.71)
            XCTAssertEqual(arg6, 99)
            XCTAssertEqual(arg7, "end")
            XCTAssertEqual(arg8, false)
            XCTAssertEqual(arg9, 100)
            expectation.fulfill()
        }
        await hubConnection.dispatchMessage(InvocationMessage(target: "testMethod", arguments: AnyEncodableArray([42, "test", true, 3.14, 2.71, 99, "end", false, 100]), streamIds: nil, headers: nil, invocationId: nil))
        await fulfillment(of: [expectation], timeout: 1)
    }
}