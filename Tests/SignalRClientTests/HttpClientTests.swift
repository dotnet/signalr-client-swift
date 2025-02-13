import XCTest

@testable import SignalRClient

let mockKey = "mock-key"

extension HttpRequest {
    init(
        mockId: String, method: HttpMethod, url: String,
        content: StringOrData? = nil,
        headers: [String: String]? = nil, timeout: TimeInterval? = nil
    ) {
        self.init(
            method: method, url: url, content: content, headers: headers,
            timeout: timeout
        )
        self.headers[mockKey] = mockId
    }
}

typealias RequestHandler = (HttpRequest) async throws -> (
    StringOrData, HttpResponse
)

enum MockClientError: Error {
    case MockIdNotFound
    case RequestHandlerNotFound
}

actor MockHttpClient: HttpClient {
    var requestHandlers: [String: RequestHandler] = [:]

    func send(request: SignalRClient.HttpRequest) async throws -> (
        StringOrData, SignalRClient.HttpResponse
    ) {
        try Task.checkCancellation()
        guard let mockId = request.headers[mockKey] else {
            XCTFail("mock Id not found")
            throw MockClientError.MockIdNotFound
        }
        guard let requestHandler = requestHandlers[mockId] else {
            XCTFail("mock request handler not found")
            throw MockClientError.RequestHandlerNotFound
        }
        return try await requestHandler(request)
    }

    func mock(mockId: String, requestHandler: @escaping RequestHandler) {
        requestHandlers[mockId] = requestHandler
    }
}

class HttpRequestTests: XCTestCase {
    func testResponseType() {
        var request = HttpRequest(method: .GET, url: "url")
        XCTAssertEqual(request.responseType, TransferFormat.text)
        request = HttpRequest(method: .GET, url: "url", content: StringOrData.string(""))
        XCTAssertEqual(request.responseType, TransferFormat.text)
        request = HttpRequest(method: .GET, url: "url", content: StringOrData.data(Data()))
        XCTAssertEqual(request.responseType, TransferFormat.binary)
    }
}

class HttpClientTests: XCTestCase {
    func testDefaultHttpClient() async throws {
        let client = DefaultHttpClient(logger: dummyLogger)
        let request = HttpRequest(method: .GET, url: "https://www.bing.com")
        let (_, response) = try await client.send(request: request)
        XCTAssertEqual(response.statusCode, 200)
    }

    func testDefaultHttpClientFail() async throws {
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .warning, logHandler: logHandler)
        let client = DefaultHttpClient(logger: logger)
        var request = HttpRequest(method: .GET, url: "htttps://www.bing.com")
        do {
            _ = try await client.send(request: request)
            XCTFail("Request should fail!")
        } catch {
        }
        logHandler.verifyLogged("Error")
        request = HttpRequest(
            method: .GET, url: "https://www.bing.com", timeout: 0.00001
        )
        do {
            _ = try await client.send(request: request)
            XCTFail("Request should fail!")
        } catch SignalRError.httpTimeoutError {
        }
        logHandler.verifyLogged("Timeout")
    }

    func testAccessTokenHttpClientUseAccessTokenFactory() async throws {
        let mockClient = MockHttpClient()
        await mockClient.mock(mockId: "bing") { request in
            XCTAssertEqual(request.headers["Authorization"], "Bearer token")
            return (
                .string("hello"), HttpResponse(statusCode: 200)
            )
        }
        let request = HttpRequest(
            mockId: "bing", method: .GET, url: "https://www.bing.com"
        )
        let client = AccessTokenHttpClient(innerClient: mockClient) {
            return "token"
        }
        let (data, response) = try await client.send(request: request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(data.convertToString(), "hello")
    }

    func testAccessTokenHttpClientUseRetry() async throws {
        let mockClient = MockHttpClient()
        let expectation = XCTestExpectation(
            description: "Overdue token should be found")
        await mockClient.mock(mockId: "bing") { request in
            let authHeader = request.headers["Authorization"]

            if authHeader == nil {
                XCTFail("No auth header found")
            }

            if authHeader == "Bearer overdue" {
                expectation.fulfill()
                return (.string(""), HttpResponse(statusCode: 401))
            }

            return (
                .string("hello"), HttpResponse(statusCode: 200)
            )
        }
        let request = HttpRequest(
            mockId: "bing", method: .GET, url: "https://www.bing.com"
        )
        let client = AccessTokenHttpClient(innerClient: mockClient) { "token" }
        await client.setAccessToken(accessToekn: "overdue")
        let (message, response) = try await client.send(request: request)
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(response.statusCode, 200)
        switch message {
        case .data(_):
            XCTFail("Invalid response type")
        case .string(let str):
            XCTAssertEqual(str, "hello")
        }
    }
}

extension AccessTokenHttpClient {
    func setAccessToken(accessToekn: String) {
        self.accessToken = accessToekn
    }
}
