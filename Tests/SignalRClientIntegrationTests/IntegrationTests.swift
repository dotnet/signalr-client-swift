
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
        // TODO - Add MessagePack support (need to add in server side)
        #if os(Linux)
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.longPolling, .json),
        ]
        #else
        let testCombinations: [(transport: HttpTransportType, hubProtocol: HubProtocolType)] = [
            (.webSockets, .json),
            (.serverSentEvents, .json),
            (.longPolling, .json),
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
}