import Foundation

public actor HubConnection {
    private static let defaultTimeout: TimeInterval = 30
    private static let defaultPingInterval: TimeInterval = 15
    private var invocationBinder: DefaultInvocationBinder
    private var invocationHandler: InvocationHandler

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
        self.serverTimeout = serverTimeout ?? HubConnection.defaultTimeout
        self.keepAliveInterval = keepAliveInterval ?? HubConnection.defaultPingInterval
        self.logger = logger
        self.retryPolicy = retryPolicy

        self.connection = connection
        self.hubProtocol = hubProtocol

        self.invocationBinder = DefaultInvocationBinder()
        self.invocationHandler = InvocationHandler()
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
        let invocationMessage = InvocationMessage(target: method, arguments: AnyEncodableArray(arguments), streamIds: nil, headers: nil, invocationId: nil)
        let data = try hubProtocol.writeMessage(message: invocationMessage)
        try await sendMessageInternal(data)
    }

    public func invoke(method: String, arguments: Any...) async throws -> Void {
        let (invocationId, tcs) = await invocationHandler.create()
        let invocationMessage = InvocationMessage(target: method, arguments: AnyEncodableArray(arguments), streamIds: nil, headers: nil, invocationId: invocationId)
        let data = try hubProtocol.writeMessage(message: invocationMessage)
        try await sendMessageInternal(data)
        _ = try await tcs.task()
    }

    public func invoke<TReturn>(method: String, arguments: Any...) async throws -> TReturn {
        let (invocationId, tcs) = await invocationHandler.create()
        invocationBinder.registerInvocation(invocationId: invocationId, types: TReturn.self)
        defer {invocationBinder.removeInvocation(invocationId: invocationId)}
        let invocationMessage = InvocationMessage(target: method, arguments: AnyEncodableArray(arguments), streamIds: nil, headers: nil, invocationId: invocationId)
        let data = try hubProtocol.writeMessage(message: invocationMessage)
        try await sendMessageInternal(data)
        if let returnVal = try await tcs.task().result.value as? TReturn {
            return returnVal
        } else {
            throw SignalRError.invalidOperation("Cannot convert the result of the invocation to the specified type.")
        }
    }

    internal func on(method: String, types: [Any.Type], handler: @escaping ([Any]) async throws -> Void) {
        invocationBinder.registerSubscription(methodName: method, types: types, handler: handler)
    }

    public func off(method: String) {
        invocationBinder.removeSubscrioption(methodName: method)
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
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) // interval in seconds to ns
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

        do {
            let hubMessage = try hubProtocol.parseMessages(input: data!, binder: invocationBinder)
            for message in hubMessage {
                await dispatchMessage(message)
            }
        } catch {
            logger.log(level: .error, message: "Error parsing messages: \(error)")
        }
    }

    func dispatchMessage(_ message: HubMessage) async {
        switch message {
            case let message as InvocationMessage:
                // Invoke a method
                if let handler = invocationBinder.getHandler(methodName: message.target) {
                    do {
                        try await handler(message.arguments.value ?? [])
                    } catch {
                        logger.log(level: .error, message: "Error invoking method: \(error)")
                    }
                }
                break
            case _ as StreamItemMessage:
                // Stream item
                break
            case let message as CompletionMessage:
                await invocationHandler.setResult(message: message)
                break
            case _ as StreamInvocationMessage:
                // Stream invocation
                break
            case _ as CancelInvocationMessage:
                // Cancel stream
                break
            case _ as PingMessage:
                // Ping
                break
            case _ as CloseMessage:
                // Close
                break
            case _ as AckMessage:
                // Ack
                break
            case _ as SequenceMessage:
                // Sequence
                break
            default:
                logger.log(level: .warning, message: "Unknown message type: \(message)")
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

    private class InvocationEntity {
        public let types: [Any.Type]
        public let callback: ([Any]) async throws -> Void

        init(types: [Any.Type], callback: @escaping ([Any]) async throws -> Void) {
            self.types = types
            self.callback = callback
        }
    }

    private struct DefaultInvocationBinder : InvocationBinder, @unchecked Sendable {
        private let lock = DispatchSemaphore(value: 1)
        private var subscriptionHandlers: [String: InvocationEntity] = [:]
        private var returnValueHandler: [String: Any.Type] = [:]

        mutating func registerSubscription(methodName: String, types: [Any.Type], handler: @escaping ([Any]) async throws -> Void) {
            lock.wait()
            defer {lock.signal()}
            subscriptionHandlers[methodName] = InvocationEntity(types: types, callback: handler)
        }

        mutating func removeSubscrioption(methodName: String) {
            lock.wait()
            defer {lock.signal()}
            subscriptionHandlers[methodName] = nil
        }

        mutating func registerInvocation(invocationId: String, types: Any.Type) {
            lock.wait()
            defer {lock.signal()}
            returnValueHandler[invocationId] = types
        }

        mutating func removeInvocation(invocationId: String) {
            lock.wait()
            defer {lock.signal()}
            returnValueHandler[invocationId] = nil
        }

        func getHandler(methodName: String) -> (([Any]) async throws -> Void)? {
            lock.wait()
            defer {lock.signal()}
            return subscriptionHandlers[methodName]?.callback
        }

        func getReturnType(invocationId: String) -> (any Any.Type)? {
            lock.wait()
            defer {lock.signal()}
            return returnValueHandler[invocationId]
        }

        func getParameterTypes(methodName: String) -> [any Any.Type] {
            lock.wait()
            defer {lock.signal()}
            return subscriptionHandlers[methodName]?.types ?? []
        }

        func getStreamItemType(streamId: String) -> (any Any.Type)? {
            lock.wait()
            defer {lock.signal()}
            return nil // not implemented
        }   
    }

    private actor InvocationHandler {
        private var invocations: [String: TaskCompletionSource<CompletionMessage>] = [:]
        private var id = 0

        func create() async -> (String, TaskCompletionSource<CompletionMessage>) {
            id = id + 1
            let tcs = TaskCompletionSource<CompletionMessage>()
            invocations[String(id)] = tcs
            return (String(id), tcs)
        }

        func setResult(message: CompletionMessage) async {
            if let tcs = invocations[message.invocationId!] {
                invocations[message.invocationId!] = nil
                if (message.error != nil) {
                    _ = await tcs.trySetResult(.failure(SignalRError.invocationError(message.error!)))
                } else {
                    _ = await tcs.trySetResult(.success(message))
                }
            }
        }

        func remove(invocationId: String, error: Error) async {
            if let tcs = invocations[invocationId] {
                invocations[invocationId] = nil
                _ = await tcs.trySetResult(.failure(error))
            }
        }
    }
}

public enum HubConnectionState {
    // The connection is stopped. Start can only be called if the connection is in this state.
    case Stopped
    case Connecting
    case Connected
    case Reconnecting
}