// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

public class HubConnectionBuilder {
    var connection: HttpConnection?
    var logHandler: LogHandler?
    var logLevel: LogLevel?
    var hubProtocol: HubProtocol?
    var serverTimeout: TimeInterval?
    var keepAliveInterval: TimeInterval?
    var url: String?
    var retryPolicy: RetryPolicy?
    var statefulReconnectBufferSize: Int?
    var httpConnectionOptions: HttpConnectionOptions = HttpConnectionOptions()

    public init() {}

    public func withLogLevel(logLevel: LogLevel) -> HubConnectionBuilder {
        self.logLevel = logLevel
        self.httpConnectionOptions.logLevel = logLevel
        return self
    }

    public func withLogHandler(logHandler: LogHandler) -> HubConnectionBuilder {
        self.logHandler = logHandler
        return self
    }

    public func withHubProtocol(hubProtocol: HubProtocolType) -> HubConnectionBuilder {
        switch hubProtocol {
        case let .json(encoder, decoder):
            self.hubProtocol = JsonHubProtocol(encoder: encoder, decoder: decoder)
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
    
    public func withUrl(url: String, options: HttpConnectionOptions) -> HubConnectionBuilder {
        self.url = url
        self.httpConnectionOptions = options
        return self
    }

    public func withStatefulReconnect(bufferSize: Int) -> HubConnectionBuilder {
        self.httpConnectionOptions.useStatefulReconnect = true
        self.statefulReconnectBufferSize = bufferSize
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

//    public func withStatefulReconnect() -> HubConnectionBuilder {
//        return withStatefulReconnect(options: StatefulReconnectOptions())
//    }
//
//    public func withStatefulReconnect(options: StatefulReconnectOptions) -> HubConnectionBuilder {
//        self.statefulReconnectBufferSize = options.bufferSize
//        self.httpConnectionOptions.useStatefulReconnect = true
//        return self
//    }

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
                             keepAliveInterval: keepAliveInterval,
                             statefulReconnectBufferSize: statefulReconnectBufferSize)
    }
}

public enum HubProtocolType {
    case json(JSONEncoder = .init(), JSONDecoder = .init())
    case messagePack
}
