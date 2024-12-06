import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - HttpRequest and HttpResponse

public enum HttpMethod: String, Sendable {
    case GET, PUT, PATCH, POST, DELETE
}

public struct HttpRequest: Sendable {
    var method: HttpMethod
    var url: String
    var content: StringOrData?
    var headers: [String: String]
    var timeout: TimeInterval
    var responseType: TransferFormat

    public init(
        method: HttpMethod, url: String, content: StringOrData? = nil,
        responseType: TransferFormat? = nil,
        headers: [String: String]? = nil, timeout: TimeInterval? = nil
    ) {
        self.method = method
        self.url = url
        self.content = content
        self.headers = headers ?? [:]
        self.timeout = timeout ?? 100
        if responseType != nil {
            self.responseType = responseType!
        } else {
            switch content {
            case .data(_):
                self.responseType = TransferFormat.binary
            default:
                self.responseType = TransferFormat.text
            }
        }
    }
}

public struct HttpResponse {
    public let statusCode: Int
}

// MARK: - HttpClient Protocol

public protocol HttpClient: Sendable {
    // Don't throw if the http call returns a status code out of [200, 299]
    func send(request: HttpRequest) async throws -> (StringOrData, HttpResponse)
}

actor DefaultHttpClient: HttpClient {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func send(request: HttpRequest) async throws -> (
        StringOrData, HttpResponse
    ) {
        let session = URLSession.shared
        do {
            let urlRequest = try request.buildURLRequest()
            let (data, response) = try await session.data(
                for: urlRequest)
            guard let httpURLResponse = response as? HTTPURLResponse else {
                throw SignalRError.invalidResponseType
            }
            let httpResponse = HttpResponse(
                statusCode: httpURLResponse.statusCode)
            let message = try data.convertToStringOrData(
                transferFormat: request.responseType)
            return (message, httpResponse)
        } catch {
            if let urlError = error as? URLError,
                urlError.code == URLError.timedOut
            {
                logger.log(
                    level: .warning, message: "Timeout from HTTP request.")
                throw SignalRError.httpTimeoutError
            }
            logger.log(
                level: .warning, message: "Error from HTTP request: \(error)")
            throw error
        }
    }
}

typealias AccessTokenFactory = () async throws -> String?

actor AccessTokenHttpClient: HttpClient {
    var accessTokenFactory: AccessTokenFactory?
    var accessToken: String?
    private let innerClient: HttpClient

    public init(
        innerClient: HttpClient,
        accessTokenFactory: AccessTokenFactory?
    ) {
        self.innerClient = innerClient
        self.accessTokenFactory = accessTokenFactory
    }

    public func setAccessTokenFactory(factory: AccessTokenFactory?) {
        self.accessTokenFactory = factory
    }

    public func send(request: HttpRequest) async throws -> (
        StringOrData, HttpResponse
    ) {
        var mutableRequest = request
        var allowRetry = true

        if let factory = accessTokenFactory,
            accessToken == nil || (request.url.contains("/negotiate?"))
        {
            // Don't retry if the request is a negotiate or if we just got a potentially new token from the access token factory
            allowRetry = false
            accessToken = try await factory()
        }

        setAuthorizationHeader(request: &mutableRequest)

        var (data, httpResponse) = try await innerClient.send(
            request: mutableRequest)

        if allowRetry && httpResponse.statusCode == 401,
            let factory = accessTokenFactory
        {
            accessToken = try await factory()
            setAuthorizationHeader(request: &mutableRequest)
            (data, httpResponse) = try await innerClient.send(
                request: mutableRequest)

            return (data, httpResponse)
        }

        return (data, httpResponse)
    }

    private func setAuthorizationHeader(request: inout HttpRequest) {
        if let token = accessToken {
            request.headers["Authorization"] = "Bearer \(token)"
        } else if accessTokenFactory != nil {
            request.headers.removeValue(forKey: "Authorization")
        }
    }
}

extension HttpRequest {
    fileprivate func buildURLRequest() throws -> URLRequest {
        guard let url = URL(string: self.url) else {
            throw SignalRError.invalidUrl(self.url)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.timeoutInterval = timeout
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        switch content {
        case .data(let data):
            urlRequest.httpBody = data
            urlRequest.setValue(
                "application/octet-stream", forHTTPHeaderField: "Content-Type")
        case .string(let strData):
            urlRequest.httpBody = strData.data(using: .utf8)
            urlRequest.setValue(
                "text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        case nil:
            break
        }
        return urlRequest
    }
}

extension HttpResponse {
    func ok() -> Bool {
        return statusCode >= 200 && statusCode < 300
    }
}
