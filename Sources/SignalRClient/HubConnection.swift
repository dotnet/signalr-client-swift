import Foundation

public actor HubConnection {
    private let defaultTimeout: TimeInterval = 30
    private let defaultPingInterval: TimeInterval = 15

    private let serverTimeout: TimeInterval
    private let keepAliveInterval: TimeInterval
    private let logger: Logger
    private let hubProtocol: HubProtocol
    private let connection: ConnectionProtocol
    private let retryPolicy: RetryPolicy
    // private let connectionState: ConnectionState

    private var connectionStarted: Bool = false
    private var receivedHandshakeResponse: Bool = false
    private var invocationId: Int = 0
    private var connectionStatus: HubConnectionState = .stopped
    private var stopping: Bool = false
    private var stopDuringStartError: Error?
    nonisolated(unsafe) private var handshakeResolver: ((HandshakeResponseMessage) -> Void)?
    nonisolated(unsafe) private var handshakeRejector: ((Error) -> Void)?

    private var stopTask: Task<Void, Error>?
    private var startTask: Task<Void, Error>?

    internal init(connection: ConnectionProtocol,
                logger: Logger,
                hubProtocol: HubProtocol,
                retryPolicy: RetryPolicy,
                serverTimeout: TimeInterval?,
                keepAliveInterval: TimeInterval?) {
        self.serverTimeout = serverTimeout ?? defaultTimeout
        self.keepAliveInterval = keepAliveInterval ?? defaultPingInterval
        self.logger = logger
        self.retryPolicy = retryPolicy

        self.connection = connection
        self.hubProtocol = hubProtocol
        // self.connectionState = ConnectionState()
    }

    public func start() async throws {
        if (connectionStatus != .stopped) {
            throw SignalRError.invalidOperation("Start client while not in a disconnected state.")
        }

        connectionStatus = .Connecting
        
        startTask = Task {
            do {
                await self.connection.onClose(handleConnectionClose)
                await self.connection.onReceive(processIncomingData)

                try await startInternal()
                connectionStatus = .Connected
            } catch {
                connectionStatus = .stopped
                logger.log(level: .debug, message: "HubConnection start failed \(error)")
                throw error
            }
        }

        try await startTask!.value
    }

    public func stop() async throws {
        // 1. Before the start, it should be disconnected. Just return
        if (connectionStatus == .stopped) {
            logger.log(level: .debug, message: "Connection is already stopped")
            return
        }

        // 2. Another stop is running, just wait for it
        if (stopping) {
            logger.log(level: .debug, message: "Connection is already stopping")
            try await stopTask?.value
            return
        }

        stopping = true
        
        // In this step, there's no other start running
        stopTask = Task {
            await stopInternal()
        }

        try await stopTask!.value
    }

    public func send(method: String, arguments: Any...) async throws {
        // Send a message
    }

    public func invoke(method: String, arguments: Any...) async throws -> Any {
        // Invoke a method
        return ""
    }

    public func on(method: String, handler: @escaping ([Any]) async -> Void) {
        // Register a handler
    }

    public func off(method: String) {
        // Unregister a handler
    }

    public func onClosed(handler: @escaping (Error?) async -> Void) {
        // Register a handler for the connection closing
    }

    public func state() -> HubConnectionState {
        return connectionStatus
    }

    private func stopInternal() async {
        // 3. Wait startInternal() to finish

        do {
            try await startTask?.value
        } catch {
            // If start failed, already in disconnected state
        }

        if (connectionStatus == .stopped) {
            return
        }

        await connection.stop(error: nil)
    }

    @Sendable private func handleConnectionClose(error: Error?) async {
        logger.log(level: .information, message: "Connection closed")
        stopDuringStartError = error ?? SignalRError.connectionAborted

        if (connectionStatus == .stopped) {
            completeClose()
            return
        }

        if (handshakeResolver != nil) {
            handshakeRejector!(SignalRError.connectionAborted)
        }

        if (stopping) {
            completeClose()
        }

        var retryCount = 0
        // reconnect
        while let interval = retryPolicy.nextRetryInterval(retryCount: retryCount) {
            if (stopping) {
                break
            }

            logger.log(level: .debug, message: "Connection reconnecting")
            connectionStatus = .Reconnecting
            do {
                try await startInternal()
                connectionStatus = .Connected
                return
            } catch {
                logger.log(level: .warning, message: "Connection reconnect failed: \(error)")
            }

            if (stopping) {
                break
            }

            retryCount += 1

            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1000))
            } catch {
                break
            }
        }

        logger.log(level: .warning, message: "Connection reconnect exceeded retry policy")
        completeClose()
    }

    // Internal for testing
    @Sendable internal func processIncomingData(_ prehandledData: StringOrData) async {
        var data: StringOrData? = prehandledData
        if (!receivedHandshakeResponse) {
            do {
                data = try await processHandshakeResponse(prehandledData)
                receivedHandshakeResponse = true
            } catch {
                // close connection
            }
        }

        if (data == nil) {
            return
        }

        // show the data now
        if case .string(let str) = data {
            logger.log(level: .debug, message: "Received data: \(str)")
        } else if case .data(let data) = data {
            logger.log(level: .debug, message: "Received data: \(data)")
        }
    }

    private func completeClose() {
        connectionStatus = .stopped
        stopping = false
    }

    private func startInternal() async throws {
        try Task.checkCancellation()

        guard stopping == false else {
            throw SignalRError.invalidOperation("Stopping is called")
        }

        logger.log(level: .debug, message: "Starting HubConnection")

        stopDuringStartError = nil
        try await connection.start(transferFormat: hubProtocol.transferFormat)

        // After connection open, perform handshake
        let version = hubProtocol.version
        // As we only support 0 now
        guard version == 0 else {
            logger.log(level: .error, message: "Unsupported handshake version: \(version)")
            throw SignalRError.unsupportedHandshakeVersion
        }

        let handshakeRequest = HandshakeRequestMessage(protocol: hubProtocol.name, version: version)

        logger.log(level: .debug, message: "Sending handshake request message.")
        async let handshakeTask = withUnsafeThrowingContinuation { continuation in 
            var hanshakeFinished: Bool = false
            handshakeResolver = { message in
                if (hanshakeFinished) {
                    return
                }
                hanshakeFinished = true
                continuation.resume(returning: message)
            }
            handshakeRejector = { error in
                if (hanshakeFinished) {
                    return
                }
                hanshakeFinished = true
                continuation.resume(throwing: error)
            }
        }

        try await sendMessageInternal(.string(HandshakeProtocol.writeHandshakeRequest(handshakeRequest: handshakeRequest)))
        logger.log(level: .debug, message: "Sent handshake request message with version: \(version), protocol: \(hubProtocol.name)")

        do {
            _ = try await handshakeTask            
            guard stopDuringStartError == nil else {
                // Connection was closed during handshake, caused by onClose or stop(). It may happen after handshake task is resolved
                throw stopDuringStartError!
            }
            logger.log(level: .debug, message: "Handshake completed")
        } catch {
            logger.log(level: .error, message: "Handshake failed: \(error)")
            throw error
        }

        logger.log(level: .debug, message: "HubConnection started")
    }

    private func sendMessageInternal(_ content: StringOrData) async throws {
        // Reset keepalive timer
        try await connection.send(content)
    }

    private func processHandshakeResponse(_ content: StringOrData) async throws -> StringOrData? {
        var remainingData: StringOrData?
        var handshakeResponse: HandshakeResponseMessage

        do {
            (remainingData, handshakeResponse) = try HandshakeProtocol.parseHandshakeResponse(data: content)
        } catch{
            logger.log(level: .error, message: "Error parsing handshake response: \(error)")
            handshakeRejector!(error)
            throw error
        }
        
        if (handshakeResponse.error != nil) {
            logger.log(level: .error, message: "Server returned handshake error: \(handshakeResponse.error!)") 
            let error = SignalRError.handshakeError(handshakeResponse.error!)
            handshakeRejector!(error)
            throw error
        } else {
            logger.log(level: .debug, message: "Handshake compeleted")
        }

        handshakeResolver!(handshakeResponse)
        return remainingData
    }
}

public enum HubConnectionState {
    // The connection is disconnected. Start can only be called if the connection is in this state.
    case stopped
    case Connecting
    case Connected
    case Reconnecting
}