// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Enums and Protocols

private enum ConnectionState: String {
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnected = "Disconnected"
    case disconnecting = "Disconnecting"
}

public struct HttpConnectionOptions {
    public var logHandler: LogHandler?
    public var logLevel: LogLevel = .information
    public var accessTokenFactory: (@Sendable () async throws -> String?)?
    public var httpClient: HttpClient?
    public var transport: HttpTransportType?
    public var skipNegotiation: Bool = false
    public var headers: [String: String]?
    public var timeout: TimeInterval?
    public var logMessageContent: Bool?
    var webSocket: AnyObject? // Placeholder for WebSocket type
    var eventSource: EventSourceAdaptor?
    var useStatefulReconnect: Bool? // Not supported yet
}

struct HttpError: Error {
    var statusCode: Int
}

// MARK: - Models

struct NegotiateResponse: Decodable {
    var connectionId: String?
    var connectionToken: String?
    var negotiateVersion: Int?
    var availableTransports: [AvailableTransport]?
    var url: String?
    var accessToken: String?
    var error: String?
    var useStatefulReconnect: Bool?

    enum CodingKeys: String, CodingKey {
        case connectionId
        case connectionToken
        case negotiateVersion
        case availableTransports
        case url
        case accessToken
        case error
        case useStatefulReconnect
    }
}

struct AvailableTransport: Decodable {
    var transport: String
    var transferFormats: [String]

    enum CodingKeys: String, CodingKey {
        case transport
        case transferFormats
    }
}

// MARK: - HttpConnection Class

actor HttpConnection: ConnectionProtocol {
    // MARK: - Properties
    private let negotiationRedirectionLimit = 100

    private var connectionState: ConnectionState = .disconnected
    private var connectionStartedSuccessfully: Bool = false
    private let httpClient: AccessTokenHttpClient
    private let logger: Logger
    private var options: HttpConnectionOptions
    private var transport: Transport?
    private var startInternalTask: Task<Void, Error>?
    private var stopTask: Task<Void, Never>?
    private var stopError: Error?
    private var accessTokenFactory: (@Sendable () async throws -> String?)?
    private var inherentKeepAlivePrivate: Bool = false

    public var features: [String: Any] = [:]
    public var baseUrl: String
    public var connectionId: String?
    public var inherentKeepAlive: Bool { 
        get async {
            return inherentKeepAlivePrivate
        }
    }

    private var onReceive: Transport.OnReceiveHandler?
    private var onClose: Transport.OnCloseHander?
    private let negotiateVersion = 1
    private var closeDuringStartError: Error? = nil

    // MARK: - Initialization

    init(url: String, options: HttpConnectionOptions = HttpConnectionOptions()) {
        precondition(!url.isEmpty, "url is required")

        self.logger = Logger(logLevel: options.logLevel, logHandler: options.logHandler ?? DefaultLogHandler())
        self.baseUrl = HttpConnection.resolveUrl(url)
        self.options = options

        self.options.logMessageContent = options.logMessageContent ?? false
        self.options.timeout = options.timeout ?? 100

        self.accessTokenFactory = options.accessTokenFactory
        self.httpClient = AccessTokenHttpClient(innerClient: options.httpClient ?? DefaultHttpClient(logger: logger), accessTokenFactory: options.accessTokenFactory)
    }

    // MARK: - Public Methods

    func onReceive(_ handler: @escaping Transport.OnReceiveHandler) async {
        onReceive = handler
    }

    func onClose(_ handler: @escaping Transport.OnCloseHander) async {
        onClose = handler
    }

    func start(transferFormat: TransferFormat = .binary) async throws {
        logger.log(level: .debug, message: "Starting connection with transfer format '\(transferFormat)'.")

        // startInternalTask make this easy:
        // - If startInternalTask is nil, start will directly stop
        // - If startInternalTask is not nil, wait it finish and then call the stop
        guard connectionState == .disconnected else {
            throw SignalRError.invalidOperation("Cannot start an HttpConnection that is not in the 'Disconnected' state. Currently it's \(connectionState)")
        }

        connectionState = .connecting

        startInternalTask = Task {
            do {
                try await self.startInternal(transferFormat: transferFormat)
                connectionStartedSuccessfully = true
            } catch {
                connectionState = .disconnected
                throw error
            }
        }

        try await startInternalTask?.value
    }

    func send(_ data: StringOrData) async throws {
        guard connectionState == .connected else {
            throw SignalRError.invalidOperation("Cannot send data if the connection is not in the 'Connected' State. Currently it's \(connectionState)")
        }

        try await transport?.send(data)
    }

    func stop(error: Error? = nil) async {
        if connectionState == .disconnected {
            logger.log(level: .debug, message: "Call to HttpConnection.stop(\(String(describing: error))) ignored because the connection is already in the disconnected state.")
            return
        }

        if connectionState == .disconnecting {
            logger.log(level: .debug, message: "Call to HttpConnection.stop(\(String(describing: error))) ignored because the connection is already in the disconnecting state.")
            await stopTask?.value
            return
        }

        connectionState = .disconnecting

        stopTask = Task {
            await self.stopInternal(error: error)
        }

        await stopTask?.value
    }

    // MARK: - Private Methods

    private func startInternal(transferFormat: TransferFormat) async throws {
        guard connectionState == .connecting else {
            throw SignalRError.connectionAborted
        }
        closeDuringStartError = nil
        
        var url = baseUrl
        await httpClient.setAccessTokenFactory(factory: accessTokenFactory)

        do {
            if options.skipNegotiation {
                if options.transport == .webSockets {
                    transport = try await constructTransport(transport: .webSockets)
                    try await startTransport(url: url, transferFormat: transferFormat)
                } else {
                    throw SignalRError.negotiationError("Negotiation can only be skipped when using the WebSocket transport directly.")
                }
            } else {
                var negotiateResponse: NegotiateResponse?
                var redirects = 0
                repeat {
                    negotiateResponse = try await getNegotiationResponse(url: url)
                    logger.log(level: .debug, message: "Negotiation response received.")

                    if connectionState == .disconnecting || connectionState == .disconnected {
                        throw SignalRError.negotiationError("The connection was stopped during negotiation.")
                    }
                    if let error = negotiateResponse?.error {
                        throw SignalRError.negotiationError(error)
                    }
                    if negotiateResponse?.url != nil {
                        url = negotiateResponse?.url ?? url
                    }
                    if let accessToken = negotiateResponse?.accessToken {
                        // Replace the current access token factory with one that uses
                        // the returned access token
                        accessTokenFactory = { return accessToken }
                        await httpClient.setAccessTokenFactory(factory: accessTokenFactory)
                    }
                    redirects += 1
                } while negotiateResponse?.url != nil && redirects < negotiationRedirectionLimit

                if redirects == negotiationRedirectionLimit && negotiateResponse?.url != nil {
                    throw SignalRError.negotiationError("Negotiate redirection limit exceeded: \(negotiationRedirectionLimit).")
                }

                logger.log(level: .debug, message: "Successfully finish the negotiation. \(String(describing: negotiateResponse))")
                try await createTransport(url: url, requestedTransport: options.transport, negotiateResponse: negotiateResponse, requestedTransferFormat: transferFormat)
            }

            if (transport is LongPollingTransport) {
                inherentKeepAlivePrivate = true
            }

            guard closeDuringStartError == nil else {
                throw closeDuringStartError!
            }

            // IMPORTANT: There should be no async code start from here. Otherwise, we may lost the control of the connection lifecycle

            connectionState = .connected
            logger.log(level: .debug, message: "The HttpConnection connected successfully.")
        } catch {
            logger.log(level: .error, message: "Failed to start the connection: \(error)")
            connectionState = .disconnected
            transport = nil
            throw error
        }
    }

    private func stopInternal(error: Error?) async {
        guard connectionState != .disconnected else {
            return
        }

        stopError = error
        closeDuringStartError = error ?? SignalRError.connectionAborted

        do {
            // startInternalTask may have several cases:
            // 1. Already finished. Just return immediately
            // 2. Still in progress. Caused by closeDuringStartError, it will throw and set transport to nil
            try await startInternalTask?.value
        } catch {
            // Ignore errors from startInternal
        }

        if transport != nil {
            do {
                try await transport?.stop(error: nil)
            } catch {
                logger.log(level: .error, message: "HttpConnection.transport.stop() threw error '\(error)'.")
                await handleConnectionClose(error: error)
            }
        } else {
            logger.log(level: .debug, message: "HttpConnection.transport is undefined in HttpConnection.stop() because start() failed.")
        }
    }

    private func getNegotiationResponse(url: String) async throws -> NegotiateResponse {
        let negotiateUrl = resolveNegotiateUrl(url: url)
        logger.log(level: .debug, message: "Sending negotiation request: \(negotiateUrl)")
        do {
            let request = HttpRequest(method: .POST, url: negotiateUrl, options: options)

            let (message, response) = try await httpClient.send(request: request)

            if response.statusCode != 200 {
                throw SignalRError.negotiationError("Unexpected status code returned from negotiate '\(response.statusCode)'")
            }

            let decoder = JSONDecoder()
            var negotiateResponse = try decoder.decode(NegotiateResponse.self, from: message.converToData())

            if negotiateResponse.negotiateVersion == nil || negotiateResponse.negotiateVersion! < 1 {
                negotiateResponse.connectionToken = negotiateResponse.connectionId
            }

            if negotiateResponse.useStatefulReconnect == true && options.useStatefulReconnect != true {
                throw SignalRError.negotiationError("Client didn't negotiate Stateful Reconnect but the server did.")
            }

            return negotiateResponse
        } catch {
            var errorMessage = "Failed to complete negotiation with the server: \(error)"
            if let httpError = error as? HttpError, httpError.statusCode == 404 {
                errorMessage += " Either this is not a SignalR endpoint or there is a proxy blocking the connection."
            }
            logger.log(level: .error, message: "\(errorMessage)")
            throw SignalRError.negotiationError(errorMessage)
        }
    }

    private func createTransport(url: String, requestedTransport: HttpTransportType?, negotiateResponse: NegotiateResponse?, requestedTransferFormat: TransferFormat) async throws {
        var connectUrl = createConnectUrl(url: url, connectionToken: negotiateResponse?.connectionToken)

        var transportExceptions: [Error] = []
        let transports = negotiateResponse?.availableTransports ?? []
        var negotiate = negotiateResponse

        for endpoint in transports {
            let transportOrError = await resolveTransportOrError(endpoint: endpoint, requestedTransport: requestedTransport, requestedTransferFormat: requestedTransferFormat, useStatefulReconnect: negotiate?.useStatefulReconnect ?? false)
            if let error = transportOrError as? Error {
                transportExceptions.append(error)
            } else if let transportInstance = transportOrError as? Transport {
                transport = transportInstance
                if negotiate == nil {
                    negotiate = try await getNegotiationResponse(url: url)
                    connectUrl = createConnectUrl(url: url, connectionToken: negotiate?.connectionToken)
                }
                do {
                    try await startTransport(url: connectUrl, transferFormat: requestedTransferFormat)
                    connectionId = negotiate?.connectionId
                    logger.log(level: .debug, message: "Using the \(endpoint.transport) transport successfully.")
                    return
                } catch {
                    logger.log(level: .error, message: "Failed to start the transport '\(endpoint.transport)': \(error)")
                    negotiate = nil
                    transportExceptions.append(error)
                    if connectionState != .connecting {
                        let message = "Failed to select transport before stop() was called."
                        logger.log(level: .debug, message: "\(message)")
                        throw SignalRError.failedToStartConnection(message)
                    }
                }
            }
        }

        if !transportExceptions.isEmpty {
            let errorsDescription = transportExceptions.map { "\($0)" }.joined(separator: " ")
            throw SignalRError.failedToStartConnection("Unable to connect to the server with any of the available transports. \(errorsDescription)")
        }

        throw SignalRError.failedToStartConnection("None of the transports supported by the client are supported by the server.")
    }

    private func startTransport(url: String, transferFormat: TransferFormat) async throws {
        await transport!.onReceive(self.onReceive)
        await transport!.onClose { [weak self] error in
            guard let self = self else { return }
            await self.handleConnectionClose(error: error)
        }

        do {
            try await transport!.connect(url: url, transferFormat: transferFormat)
        } catch {
            await transport!.onReceive(nil)
            await transport!.onClose(nil)
            throw error
        }
    }

    private func handleConnectionClose(error: Error?) async {
        logger.log(level: .debug, message: "HttpConnection.stopConnection(\(String(describing: error))) called while in state \(connectionState).")

        transport = nil

        let finalError = stopError ?? error
        stopError = nil
        closeDuringStartError = finalError ?? SignalRError.connectionAborted

        if connectionState == .disconnected {
            logger.log(level: .debug, message: "Call to HttpConnection.stopConnection(\(String(describing: finalError))) was ignored because the connection is already in the disconnected state.")
            return
        }

        if (connectionState == .connecting) {
            // connecting means start still control the lifetime. As we set closeDuringStartError, it throws there.
            logger.log(level: .debug, message: "Call to HttpConnection.stopConnection(\(String(describing: finalError))) was ignored because the connection is already in the connecting state.")
            return
        }

        if let error = finalError {
            logger.log(level: .error, message: "Connection disconnected with error '\(error)'.")
        } else {
            logger.log(level: .information, message: "Connection disconnected.")
        }

        connectionId = nil
        await completeConnectionClose(error: finalError)
    }

    // Should be called whenever connection is started (start() doesn't throw and connection is closed)
    private func completeConnectionClose(error: Error?) async {
        connectionState = .disconnected

        // There's a chance that we call close() and status changed to disconnecting and startinteral throws.
        // We should not call onclose again
        if connectionStartedSuccessfully {
            connectionStartedSuccessfully = false
                await self.onClose?(error)
        }
    }

    // MARK: - Helper Methods

    private static func resolveUrl(_ url: String) -> String {
        // Implement URL resolution logic if necessary
        return url
    }

    private func resolveNegotiateUrl(url: String) -> String {
        var negotiateUrlComponents = URLComponents(string: url)!
        if !negotiateUrlComponents.path.hasSuffix("/") {
            negotiateUrlComponents.path += "/"
        }
        negotiateUrlComponents.path += "negotiate"
        var queryItems = negotiateUrlComponents.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "negotiateVersion" }) {
            queryItems.append(URLQueryItem(name: "negotiateVersion", value: "\(negotiateVersion)"))
        }
        if let useStatefulReconnect = options.useStatefulReconnect, useStatefulReconnect {
            queryItems.append(URLQueryItem(name: "useStatefulReconnect", value: "true"))
        }
        negotiateUrlComponents.queryItems = queryItems
        return negotiateUrlComponents.url!.absoluteString
    }

    private func createConnectUrl(url: String, connectionToken: String?) -> String {
        guard let token = connectionToken else { return url }
        var urlComponents = URLComponents(string: url)!
        var queryItems = urlComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "id", value: token))
        urlComponents.queryItems = queryItems
        return urlComponents.url!.absoluteString
    }

    private func constructTransport(transport: HttpTransportType) async throws -> Transport {
        switch transport {
        case .webSockets:
            return WebSocketTransport(
                accessTokenFactory: accessTokenFactory,
                logger: logger,
                headers: options.headers ?? [:]
            )
        case .serverSentEvents:
            let accessToken = await self.httpClient.accessToken
            return ServerSentEventTransport(httpClient: self.httpClient, accessToken: accessToken, logger: logger, options: options)
        case .longPolling:
            return LongPollingTransport(httpClient: httpClient, logger: logger, options: options)
        default:
            throw SignalRError.unsupportedTransport("Unkonwn transport type '\(transport)'.")
        }
    }

    private func resolveTransportOrError(endpoint: AvailableTransport, requestedTransport: HttpTransportType?, requestedTransferFormat: TransferFormat, useStatefulReconnect: Bool) async -> Any {
        guard let transportType = HttpTransportType.from(endpoint.transport) else {
            logger.log(level: .debug, message: "Skipping transport '\(endpoint.transport)' because it is not supported by this client.")
            return SignalRError.unsupportedTransport("Skipping transport '\(endpoint.transport)' because it is not supported by this client.")
        }

        if transportMatches(requestedTransport: requestedTransport, actualTransport: transportType) {
            let transferFormats = endpoint.transferFormats.compactMap { TransferFormat($0) }
            if transferFormats.contains(requestedTransferFormat) {
                do {
                    features["reconnect"] = (transportType == .webSockets && useStatefulReconnect) ? true : nil
                    let constructedTransport = try await constructTransport(transport: transportType)
                    return constructedTransport
                } catch {
                    return error
                }
            } else {
                logger.log(level: .debug, message: "Skipping transport '\(transportType)' because it does not support the requested transfer format '\(requestedTransferFormat)'.")
                return SignalRError.unsupportedTransport("'\(transportType)' does not support \(requestedTransferFormat).")
            }
        } else {
            logger.log(level: .debug, message: "Skipping transport '\(transportType)' because it was disabled by the client.")
            return SignalRError.unsupportedTransport("'\(transportType)' is disabled by the client.")
        }
    }

    private func transportMatches(requestedTransport: HttpTransportType?, actualTransport: HttpTransportType) -> Bool {
        guard let requestedTransport = requestedTransport else { return true } // Allow any the transport if options is not set
        return requestedTransport.contains(actualTransport)
    }

    private func buildURLRequest(url: String, method: String?, content: Data?, headers: [String: String]?, timeout: TimeInterval?) -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: url)!)
        urlRequest.httpMethod = method ?? "GET"
        urlRequest.httpBody = content
        if let headers = headers {
            for (key, value) in headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let timeout = timeout {
            urlRequest.timeoutInterval = timeout
        }
        return urlRequest
    }
}
