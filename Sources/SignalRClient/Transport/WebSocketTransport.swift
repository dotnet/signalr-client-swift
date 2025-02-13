import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

actor WebSocketTransport: Transport {
    private let logger: Logger
    private let accessTokenFactory: (@Sendable() async throws -> String?)?
    private let headers: [String: String]
    private let webSocketConnection: WebSocketConnection

    private var transferFormat: TransferFormat = .text

    init(accessTokenFactory: (@Sendable () async throws -> String?)?,
         logger: Logger,
         headers: [String: String],
         websocket: WebSocketConnection? = nil) {
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.headers = headers
        self.webSocketConnection = websocket ?? DefaultWebSocketConnection(logger: logger)
    }

    func onReceive(_ handler: OnReceiveHandler?) async {
        await self.webSocketConnection.onReceive(handler)
    }

    func onClose(_ handler: OnCloseHander?) async {
        await self.webSocketConnection.onClose(handler)
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        self.logger.log(level: .debug, message: "(WebSockets transport) Connecting.")

        self.transferFormat = transferFormat
        var urlComponents = URLComponents(url: URL(string: url)!, resolvingAgainstBaseURL: false)!
        if urlComponents.scheme == "http" {
            urlComponents.scheme = "ws"
        } else if urlComponents.scheme == "https" {
            urlComponents.scheme = "wss"
        }

        // Add token to query
        if let factory = accessTokenFactory {
            let token = try await factory()
            urlComponents.queryItems = [URLQueryItem(name: "access_token", value: token)]
        }

        var request = URLRequest(url: urlComponents.url!)

        // Add headeres
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        try await webSocketConnection.connect(request: request, transferFormat: transferFormat)
    }

    func send(_ data: StringOrData) async throws {
        try await webSocketConnection.send(data)
    }

    func stop(error: Error?) async throws {
        try await webSocketConnection.stop(error: error)
    }

    protocol WebSocketConnection {
        func connect(request: URLRequest, transferFormat: TransferFormat) async throws
        func send(_ data: StringOrData) async throws
        func stop(error: Error?) async throws
        func onReceive(_ handler: OnReceiveHandler?) async
        func onClose(_ handler: OnCloseHander?) async
    }

    #if os(Linux)
        private actor DefaultWebSocketConnection: WebSocketConnection {
            func connect(request: URLRequest, transferFormat: TransferFormat) async throws {
                throw SignalRError.unsupportedTransport("WebSockets transport is not supported on Linux")
            }

            func send(_ data: StringOrData) async throws {
                throw SignalRError.unsupportedTransport("WebSockets transport is not supported on Linux")
            }

            func stop(error: (any Error)?) async throws {
                throw SignalRError.unsupportedTransport("WebSockets transport is not supported on Linux")
            }

            func onReceive(_ handler: WebSocketTransport.OnReceiveHandler?) async {
            }

            func onClose(_ handler: WebSocketTransport.OnCloseHander?) async {
            }

            init(logger: Logger) {
            }
        }
    #else
        private actor DefaultWebSocketConnection: NSObject, WebSocketConnection, URLSessionWebSocketDelegate {
            private let logger: Logger
            private let openTcs: TaskCompletionSource<Void> = TaskCompletionSource()

            private var urlSession: URLSession?
            private var websocket: URLSessionWebSocketTask?
            private var receiveTask: Task<Void, Never>?
            private var onReceive: OnReceiveHandler?
            private var onClose: OnCloseHander?

            private var closed: Bool = false

            init(logger: Logger) {
                self.logger = logger
            }

            func connect(request: URLRequest, transferFormat: TransferFormat) async throws {
                urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
                websocket = urlSession!.webSocketTask(with: request)

                guard websocket != nil else {
                    throw SignalRError.failedToStartConnection("(WebSockets transport) WebSocket is nil")
                }

                websocket!.resume() // connect but it won't throw even failure

                receiveTask = Task { [weak self] in
                    guard let self = self else { return }
                    await receiveMessage()
                }

                // wait for startTcs to be completed before returning from connect
                // this is to ensure that the connection is truely established
                try await openTcs.task()
            }

            func send(_ data: StringOrData) async throws {
                guard let ws = self.websocket, ws.state == .running else {
                    throw SignalRError.invalidOperation("(WebSockets transport) Cannot send until the transport is connected")
                }

                switch data {
                case .string(let str):
                    try await ws.send(URLSessionWebSocketTask.Message.string(str))
                case .data(let data):
                    try await ws.send(URLSessionWebSocketTask.Message.data(data))
                }
            }

            func stop(error: Error?) async {
                if closed {
                    return
                }
                closed = true

                urlSession?.finishTasksAndInvalidate() // Prevent new task from being created
                websocket?.cancel() // Close the current connection

                if await openTcs.trySetResult(.failure(error ?? SignalRError.connectionAborted)) == true {
                    receiveTask?.cancel() // Cancel the receive task
                } else {
                    await receiveTask?.value // Wait for the receive task to complete
                    await onClose?(error) // Call the close handler
                }
            }

            func onReceive(_ handler: OnReceiveHandler?) async {
                onReceive = handler
            }

            func onClose(_ handler: OnCloseHander?) async {
                onClose = handler
            }

            nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
                logger.log(level: .debug, message: "(WebSockets transport) URLSession didCompleteWithError: \(String(describing: error))")

                Task {
                    await stop(error: error)
                }
            }

            // When receive websocket close message?
            nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
                logger.log(level: .debug, message: "(WebSockets transport) URLSession didCloseWith: \(closeCode)")

                Task {
                    await stop(error: nil)
                }
            }

            nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
                logger.log(level: .debug, message: "(WebSockets transport) urlSession didOpenWithProtocol invoked. WebSocket open")

                Task {
                    if await openTcs.trySetResult(.success(())) == true {
                        logger.log(level: .debug, message: "(WebSockets transport) WebSocket connected")
                    }
                }
            }

            private func receiveMessage() async {
                guard let websocket: URLSessionWebSocketTask = websocket else {
                    logger.log(level: .error, message: "(WebSockets transport) WebSocket is nil")
                    return 
                }

                do {
                    while !Task.isCancelled {
                        let message = try await websocket.receive()

                        switch message {
                        case .string(let text):
                            logger.log(level: .debug, message: "(WebSockets transport) Received message: \(text)")
                            await onReceive?(.string(text))
                        case .data(let data):
                            await onReceive?(.data(data))
                        }
                    }
                } catch {
                    logger.log(level: .debug, message: "Websocket receive error : \(error)")
                }
            }
        }
    #endif
}
