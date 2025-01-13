
import XCTest
@testable import SignalRClient

class IntegrationTests: XCTestCase {
    private var url: String?

    override func setUpWithError() throws {
        guard let url = ProcessInfo.processInfo.environment["SIGNALR_INTEGRATION_TEST_URL"] else {
            throw XCTSkip("Skipping integration tests because SIGNALR_INTEGRATION_TEST_URL is not set.")
        }
        self.url = url
    }

    func testConnect() async throws {
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .messagePack),
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            (.webSockets, .messagePack),
            (.serverSentEvents, .messagePack),
            (.longPolling, .messagePack),
        ]
        #endif

        for (transport, hubProtocol) in testCombinations {
            do {
                try await testConnectCore(transport: transport, hubProtocol: hubProtocol)
            } catch {
                XCTFail("Failed to connect with transport: \(transport) and hubProtocol: \(hubProtocol)")
            }
        }
    }

    private func testConnectCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: .information)
            .build()

        try await connection.start()
    }

    func testSendAndOn() async throws {
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .messagePack),
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            (.webSockets, .messagePack),
            (.serverSentEvents, .messagePack),
            (.longPolling, .messagePack),
        ]
        #endif

        for (transport, hubProtocol) in testCombinations {
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: "hello")
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: 1)
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: 1.2)
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: true)
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: [1, 2, 3])
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: ["key": "value"])
            try await testSendAndOnCore(transport: transport, hubProtocol: hubProtocol, item: CustomClass(str: "Hello, World!", arr: [1, 2, 3]))
        }
    }

    func testSendAndOnCore<T: Equatable>(transport: HttpTransportType, hubProtocol: HubProtocolType, item: T) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: .information)
            .build()

        let expectation = expectation(description: "Message received")
        let message1 = "Hello, World!"

        await connection.on("EchoBack") { (arg1: String, arg2: T) in
            XCTAssertEqual(arg1, message1)
            XCTAssertEqual(arg2, item)
            expectation.fulfill()
        }

        do {
            try await connection.start()
            try await connection.send(method: "Echo", arguments: message1, item)
        } catch {
            XCTFail("Failed to send and receive messages with transport: \(transport) and hubProtocol: \(hubProtocol)")
        }
        
        await fulfillment(of: [expectation], timeout: 1)
    }

    func testInvoke() async throws {
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .messagePack),
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            (.webSockets, .messagePack),
            (.serverSentEvents, .messagePack),
            (.longPolling, .messagePack),
        ]
        #endif

        for (transport, hubProtocol) in testCombinations {
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: "hello")
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: 1)
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: 1.2)
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: true)
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: [1, 2, 3])
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: ["key": "value"])
            try await testInvokeCore(transport: transport, hubProtocol: hubProtocol, item: CustomClass(str: "Hello, World!", arr: [1, 2, 3]))
        }
    }

    private func testInvokeCore<T: Equatable>(transport: HttpTransportType, hubProtocol: HubProtocolType, item: T) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: .information)
            .build()
        
        try await connection.start()

        let message1 = "Hello, World!"
        let result: T = try await connection.invoke(method: "Invoke", arguments: message1, item)
        XCTAssertEqual(result, item)
    }

    func testStream() async throws {
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .messagePack),
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            (.webSockets, .messagePack),
            (.serverSentEvents, .messagePack),
            (.longPolling, .messagePack),
        ]
        #endif

        for (transport, hubProtocol) in testCombinations {
            try await testStreamCore(transport: transport, hubProtocol: hubProtocol)
        }
    }

    private func testStreamCore(transport: HttpTransportType, hubProtocol: HubProtocolType) async throws {
        let connection = HubConnectionBuilder()
            .withUrl(url: url!, transport: transport)
            .withHubProtocol(hubProtocol: hubProtocol)
            .withLogLevel(logLevel: .information)
            .build()

        try await connection.start()

        let messages: [String] = ["a", "b", "c"]
        let stream: any StreamResult<String> = try await connection.stream(method: "Stream")
        var i = 0
        for try await item in stream.stream {
            XCTAssertEqual(item, messages[i])
            i = i + 1
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
}