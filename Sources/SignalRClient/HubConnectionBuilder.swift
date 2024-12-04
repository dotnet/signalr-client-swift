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

    public init() {}
    
    public func withLogLevel(logLevel: LogLevel) -> HubConnectionBuilder{
        self.logLevel = logLevel
        return self
    }
    
    public func withLogHandler(logHandler: LogHandler) -> HubConnectionBuilder{
        self.logHandler = logHandler
        return self
    }

    // public func withHubProtocol(hubProtocol: HubProtocol) -> HubConnectionBuilder {
    //     self.hubProtocol = hubProtocol
    //     return self
    // }

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

    public func withRetryPolicy(retryPolicy: RetryPolicy) -> HubConnectionBuilder {
        self.retryPolicy = retryPolicy
        return self
    }

    public func build() -> HubConnection {
        guard let url = url else {
            fatalError("url must be set with .withUrl(String:)")
        }

        let connection = connection ?? HttpConnection(url: url)
        let logger = Logger(logLevel: logLevel, logHandler: logHandler ?? OSLogHandler())
        let hubProtocol = hubProtocol ?? JsonHubProtocol()
        let retryPolicy = retryPolicy ?? DefaultRetryPolicy(retryDelays: [0, 1, 2])

        return HubConnection(connection: connection,
                             logger: logger,
                             hubProtocol: hubProtocol,
                             retryPolicy: retryPolicy,
                             serverTimeout: serverTimeout,
                             keepAliveInterval: keepAliveInterval)
    }
}
