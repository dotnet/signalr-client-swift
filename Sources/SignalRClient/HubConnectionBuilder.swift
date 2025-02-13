// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

public class HubConnectionBuilder {
    private var connection: HttpConnection?
    private var logHandler: LogHandler?
    private var logLevel: LogLevel?
    private var hubProtocol: HubProtocol?
    private var serverTimeout: TimeInterval?
    private var keepAliveInterval: TimeInterval?
    private var url: String?
    private var retryPolicy: RetryPolicy?
    private var httpConnectionOptions: HttpConnectionOptions = HttpConnectionOptions()

    public init() {}
    
    public func withLogLevel(logLevel: LogLevel) -> HubConnectionBuilder{
        self.logLevel = logLevel
        self.httpConnectionOptions.logLevel = logLevel
        return self
    }
    
    public func withLogHandler(logHandler: LogHandler) -> HubConnectionBuilder{
        self.logHandler = logHandler
        return self
    }

    public func withHubProtocol(hubProtocol: HubProtocolType) -> HubConnectionBuilder {
        switch hubProtocol {
            case .json:
                self.hubProtocol = JsonHubProtocol()
        case .messagePack:
            self.hubProtocol = MessagePackHubProtocol()
        }
        return self
    }

    public func withServerTimeout(serverTimeout: TimeInterval) -> HubConnectionBuilder {
        self.serverTimeout = serverTimeout
        return self
    }

    public func withKeepAliveInterval(keepAliveInterval: TimeInterval) -> HubConnectionBuilder {
        self.keepAliveInterval = keepAliveInterval
        return self
    }

    public func withUrl(url: String) -> HubConnectionBuilder {
        self.url = url
        return self
    }

    public func withUrl(url: String, transport: HttpTransportType) -> HubConnectionBuilder {
        self.url = url
        self.httpConnectionOptions.transport = transport
        return self
    }

    public func withAutomaticReconnect() -> HubConnectionBuilder {
        self.retryPolicy = DefaultRetryPolicy(retryDelays: [0, 2, 10, 30])
        return self
    }

    public func withAutomaticReconnect(retryPolicy: RetryPolicy) -> HubConnectionBuilder {
        self.retryPolicy = retryPolicy
        return self
    }

    public func withAutomaticReconnect(retryDelays: [TimeInterval]) -> HubConnectionBuilder {
        self.retryPolicy = DefaultRetryPolicy(retryDelays: retryDelays)
        return self
    }

    public func build() -> HubConnection {
        guard let url = url else {
            fatalError("url must be set with .withUrl(String:)")
        }

        let connection = connection ?? HttpConnection(url: url, options: httpConnectionOptions)
        let logger = Logger(logLevel: logLevel, logHandler: logHandler ?? DefaultLogHandler())
        let hubProtocol = hubProtocol ?? JsonHubProtocol()
        let retryPolicy = retryPolicy ?? DefaultRetryPolicy(retryDelays: []) // No retry by default

        return HubConnection(connection: connection,
                             logger: logger,
                             hubProtocol: hubProtocol,
                             retryPolicy: retryPolicy,
                             serverTimeout: serverTimeout,
                             keepAliveInterval: keepAliveInterval)
    }
}

public enum HubProtocolType {
    case json
    case messagePack
}
