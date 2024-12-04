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

    private var connectionStarted: Bool = false
    private var receivedHandshakeResponse: Bool = false
    private var invocationId: Int = 0
    private var connectionStatus: HubConnectionState = .Stopped
    private var stopping: Bool = false
    private var stopDuringStartError: Error?
    nonisolated(unsafe) private var handshakeResolver: ((HandshakeResponseMessage) -> Void)?
    nonisolated(unsafe) private var handshakeRejector: ((Error) -> Void)?

    private var stopTask: Task<Void, Never>?
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
    }

    public func start() async throws {
        if (connectionStatus != .Stopped) {
            throw SignalRError.invalidOperation("Start client while not in a stopped state.")
        }

        connectionStatus = .Connecting
        
        startTask = Task {
            do {
                await self.connection.onClose(handleConnectionClose)
                await self.connection.onReceive(processIncomingData)

                try await startInternal()
                connectionStatus = .Connected
                logger.log(level: .debug, message: "HubConnection started")
            } catch {
                connectionStatus = .Stopped
                stopping = false
                logger.log(level: .debug, message: "HubConnection start failed \(error)")
                throw error
            }
        }

        try await startTask!.value
    }

    public func stop() async {
        // 1. Before the start, it should be Stopped. Just return
        if (connectionStatus == .Stopped) {
            logger.log(level: .debug, message: "Connection is already stopped")
            return
        }

        // 2. Another stop is running, just wait for it
        if (stopping) {
            logger.log(level: .debug, message: "Connection is already stopping")
            await stopTask?.value
            return
        }

        stopping = true
        
        // In this step, there's no other start running
        stopTask = Task {
            await stopInternal()
        }

        await stopTask!.value
    }

    public func send(method: String, arguments: Any...) async throws {
        // let message = InvocationMessage(target: method, arguments: arguments.map { AnyCodable($0) }, streamIds: nil, headers: nil, invocationId: nil)
        // let payload = try hubProtocol.writeMessage(message: message)
        // try await sendMessageInternal(payload)
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
        if (connectionStatus == .Stopped) {
            return
        }

        let startTask = self.startTask

        stopDuringStartError = SignalRError.connectionAborted
        if (handshakeRejector != nil) {
            handshakeRejector!(SignalRError.connectionAborted)
        }

        await connection.stop(error: nil)

        do {
            try await startTask?.value
        } catch {
            // If start failed, already in stopped state
        }
    }

    @Sendable internal func handleConnectionClose(error: Error?) async {
        logger.log(level: .information, message: "Connection closed")
        stopDuringStartError = error ?? SignalRError.connectionAborted

        if (connectionStatus == .Stopped) {
            completeClose()
            return
        }

        stopDuringStartError = SignalRError.connectionAborted
        if (handshakeResolver != nil) {
            handshakeRejector!(SignalRError.connectionAborted)
        }

        if (stopping) {
            completeClose()
        }

        // Several status possible
        // 1. Connecting: In this case, we're still in the control of start(), don't reconnect here but let start() fail (throw error in startInternal())
        // 2. Connected: In this case, we should reconnect
        // 3. Reconnecting: In this case, we're in the control of previous reconnect(), let that function handle the reconnection

        if (connectionStatus == .Connected) {
            do {
                try await reconnect()
            } catch {
                logger.log(level: .warning, message: "Connection reconnect failed: \(error)")
            }
        }
    }

    private func reconnect() async throws {
        var retryCount = 0
        // reconnect
        while let interval = retryPolicy.nextRetryInterval(retryCount: retryCount) {
            try Task.checkCancellation()
            if (stopping) {
                break
            }

            logger.log(level: .debug, message: "Connection reconnecting")
            connectionStatus = .Reconnecting
            do {
                try await startInternal()
                // DO we need to check status here?
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
    @Sendable internal func processIncomingData(_ prehandledData: StringOrData) {
        var data: StringOrData? = prehandledData
        if (!receivedHandshakeResponse) {
            do {
                data = try processHandshakeResponse(prehandledData)
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
        connectionStatus = .Stopped
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

        receivedHandshakeResponse = false
        let handshakeRequest = HandshakeRequestMessage(protocol: hubProtocol.name, version: version)

        logger.log(level: .debug, message: "Sending handshake request message.")

        do {
            _ = try await withUnsafeThrowingContinuation { continuation in 
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

                // Send handshake request
                Task {
                    do {
                        try await self.sendMessageInternal(.string(HandshakeProtocol.writeHandshakeRequest(handshakeRequest: handshakeRequest)))
                        logger.log(level: .debug, message: "Sent handshake request message with version: \(version), protocol: \(hubProtocol.name)")
                    } catch {
                        self.handshakeRejector!(error)
                    }
                }
            }

            guard stopDuringStartError == nil else {
                throw stopDuringStartError!
            }

            logger.log(level: .debug, message: "Handshake completed")
        } catch {
            logger.log(level: .error, message: "Handshake failed: \(error)")
            throw error
        }
    }

    private func sendMessageInternal(_ content: StringOrData) async throws {
        // Reset keepalive timer
        try await connection.send(content)
    }

    private func processHandshakeResponse(_ content: StringOrData) throws -> StringOrData? {
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
    // The connection is stopped. Start can only be called if the connection is in this state.
    case Stopped
    case Connecting
    case Connected
    case Reconnecting
}