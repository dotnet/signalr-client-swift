
import XCTest
@testable import SignalRClient

class IntegrationTests: XCTestCase {
    private var url: String?
    private let logLevel: LogLevel = .debug
    #if os(Linux)
        private let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .messagePack),
            (.longPolling, .json),
        ]
    #else
        private let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            (.webSockets, .messagePack),
            (.longPolling, .messagePack),
        ]
    #endif

    override func setUpWithError() throws {
        guard let url = ProcessInfo.processInfo.environment["SIGNALR_INTEGRATION_TEST_URL"] else {
            throw XCTSkip("Skipping integration tests because SIGNALR_INTEGRATION_TEST_URL is not set.")
        }
        self.url = url
    }

    func testConnect() async throws {
        for (transport, hubProtocol) in testCombinations {
            do {
                try await whenTaskTimeout({ try await self.testConnectCore(transport: transport, hubProtocol: hubProtocol) }, timeout: 1)
            } catch {
                XCTFail("Failed to connect with transport: \(transport) and hubProtocol: \(hubProtocol)")
            }
        }
    }

    private func testConnectCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        print("testConnectCore with transport: \(transport) and hubProtocol: \(hubProtocol)")
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await run() {
            try await connection.start()
        } defer: {
            await connection.stop()
        }
    }

    func testMultipleConnectection() async throws {
        for (transport, hubProtocol) in testCombinations {
            let count = 10 // DefaultUrlSession has 5 connections
            var connections: [HubConnection] = []
            do {
                for _ in 0 ..< count {
                    let connection = HubConnectionBuilder()
                        .withUrl(url: url!, transport: transport)
                        .withHubProtocol(hubProtocol: hubProtocol)
                        .withLogLevel(logLevel: logLevel)
                        .build()
                    try await whenTaskTimeout(connection.start, timeout: 1)
                    connections.append(connection)
                }
            } catch {
                XCTFail("Failed to establish multible connection with transport: \(transport) and hubProtocol: \(hubProtocol)")
            }
            for connection in connections {
                await connection.stop()
            }
        }
    }

    func testSendAndOn() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: "hello")}, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: 1) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: 1.2) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: true) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: [1, 2, 3]) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: ["key": "value"]) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: CustomClass(str: "Hello, World!", arr: [1, 2, 3]))}, timeout: 1)
        }
    }

    func testSendAndOnCore<T: Equatable>(transport: HttpTransportType, hubProtocol: HubProtocolType, item: T) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        let expectation = expectation(description: "Message received")
        let message1 = "Hello, World!"

        await connection.on("EchoBack") { (arg1: String, arg2: T) in
            XCTAssertEqual(arg1, message1)
            XCTAssertEqual(arg2, item)
            expectation.fulfill()
        }

        try await connection.start()
        try await run() {
            do {
                try await connection.send(method: "Echo", arguments: message1, item)
            } catch {
                XCTFail("Failed to send and receive messages with transport: \(transport) and hubProtocol: \(hubProtocol)")
            }

            await fulfillment(of: [expectation], timeout: 1)
        } defer: {
            await connection.stop()
        }
    }

    func testInvoke() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: "hello") }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: 1) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: 1.2) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: true) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: [1, 2, 3]) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: ["key": "value"]) }, timeout: 1)
            try await whenTaskTimeout({ try await self.testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: CustomClass(str: "Hello, World!", arr: [1, 2, 3])) }, timeout: 1)
        }
    }

    private func testInvokeCore<T: Equatable>(transport: HttpTransportType, hubProtocol: HubProtocolType, item: T) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await connection.start()

        try await run() {
            let message1 = "Hello, World!"
            let result: T = try await connection.invoke(method: "Invoke", arguments: message1, item)
            XCTAssertEqual(result, item)
        } defer: {
            await connection.stop()
        }
    }

    func testInvokeWithoutReturn() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({ try await self.testInvokeWithoutReturnCore(transport: transport, hubProtocol: hubProtocol) }, timeout: 1)
        }
    }

    private func testInvokeWithoutReturnCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await connection.start()

        try await run() {
            let message1 = "Hello, World!"
            try await connection.invoke(method: "InvokeWithoutReturn", arguments: message1)
        } defer: {
            await connection.stop()
        }
    }

    func testStream() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({ try await self.testStreamCore(transport: transport, hubProtocol: hubProtocol) }, timeout: 1)
        }
    }

    private func testStreamCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await connection.start()

        try await run() {
            let messages: [String] = ["a", "b", "c"]
            let stream: any StreamResult<String> = try await connection.stream(method: "Stream")
            var i = 0
            for try await item in stream.stream {
                XCTAssertEqual(item, messages[i])
                i = i + 1
            }
        } defer: {
            await connection.stop()
        }
    }

    func testClientResult() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({ try await self.testClientResultCore(transport: transport, hubProtocol: hubProtocol) }, timeout: 1)
        }
    }

    private func testClientResultCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await connection.start()

        try await run() {
            let expectMessage = "Hello, World!"
            let expectation = XCTestExpectation(description: "ClientResult received")
            await connection.on("EchoBack") { (message: String) in
                XCTAssertEqual(expectMessage, message)
                expectation.fulfill()
            }
            await connection.on("ClientResult") { (message: String) in
                XCTAssertEqual(expectMessage, message)
                return expectMessage
            }
            try await connection.invoke(method: "InvokeWithClientResult", arguments: expectMessage)
            await fulfillment(of: [expectation], timeout: 1.0)
        } defer: {
            await connection.stop()
        }
    }

    func testClientResultWithNull() async throws {
        for (transport, hubProtocol) in testCombinations {
            try await whenTaskTimeout({ try await self.testClientResultWithNullCore(transport: transport, hubProtocol: hubProtocol) }, timeout: 1)
        }
    }

    private func testClientResultWithNullCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: logLevel)
            .build()

        try await connection.start()

        try await run() {
            let expectMessage = "Hello, World!"
            let expectation = XCTestExpectation(description: "ClientResult received")
            await connection.on("EchoBack") { (message: String) in
                XCTAssertEqual("received", message)
                expectation.fulfill()
            }
            await connection.on("ClientResult") { (message: String) in
                XCTAssertEqual(expectMessage, message)
                return
            }

            try await connection.invoke(method: "invokeWithEmptyClientResult", arguments: expectMessage)
            await fulfillment(of: [expectation], timeout: 1.0)
        } defer: {
            await connection.stop()
        }
    }

    class CustomClass: Codable, Equatable {
        static func == (lhs: IntegrationTests.CustomClass, rhs: IntegrationTests.CustomClass) -> Bool {
            return lhs.str == rhs.str && lhs.arr == rhs.arr
        }

        var str: String
        var arr: [Int]

        init(str: String, arr: [Int]) {
            self.str = str
            self.arr = arr
        }
    }

    func whenTaskTimeout(_ task: @escaping () async throws -> Void, timeout: TimeInterval) async throws -> Void {
        let expectation = XCTestExpectation(description: "Task should finish")
        let wrappedTask = Task {
            try await task()
            expectation.fulfill()
        }
        defer { wrappedTask.cancel() }

        await fulfillment(of: [expectation], timeout: timeout)
    }

    func run<T>(_ operation: () async throws -> T,
                defer deferredOperation: () async throws -> Void,
                line: UInt = #line) async throws -> T {
        do {
            let result = try await operation()
            try await deferredOperation()
            return result
        } catch {
            try await deferredOperation()
            XCTFail(String(describing: error), file: #file, line: line)
            throw error
        }
    }
}
