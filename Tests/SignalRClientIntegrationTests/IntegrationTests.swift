
import XCTest
@testable import SignalRClient

class IntegrationTests: XCTestCase {
    private var url: String?

    override func setUpWithError() throws {
        // guard let url = ProcessInfo.processInfo.environment["SIGNALR_INTEGRATION_TEST_URL"] else {
        //     throw XCTSkip("Skipping integration tests because SIGNALR_INTEGRATION_TEST_URL is not set.")
        // }
        let url = "http://localhost:8080/test"
        self.url = url
    }

    func testConnect() async throws {
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            // (.serverSentEvents, .json),
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            // (.webSockets, .messagePack),
            (.serverSentEvents, .json),
            (.longPolling, .json),
            // (.longPolling, .messagePack)
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
            .withLogLevel(logLevel: .debug)
            .build()

        try await connection.start()
    }

    // func testInvoke() throws {
    //     let expectation = self.expectation(description: "Invoke")
    //     connection?.invoke(method: "TestMethod", "TestParam") { error in
    //         if error == nil {
    //             expectation.fulfill()
    //         }
    //     }
    //     wait(for: [expectation], timeout: 10.0)
    // }

    // func testStream() throws {
    //     let expectation = self.expectation(description: "Stream")
    //     let stream = connection?.stream(method: "TestStreamMethod", "TestParam")
    //     stream?.observe { (value: Int?) in
    //         if value == nil {
    //             expectation.fulfill()
    //         }
    //     }
    //     stream?.start()
    //     wait(for: [expectation], timeout: 10.0)
    // }
}