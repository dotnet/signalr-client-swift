import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


final class WebSocketTransport: NSObject, Transport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let logger: Logger
    private let accessTokenFactory: (@Sendable() async throws -> String?)?
    private let logMessageContent: Bool
    private let headers: [String: String]
    private let stopped: AtomicState<Bool> = AtomicState(initialState: false)
    private let openTcs: TaskCompletionSource<Void> = TaskCompletionSource()

    private var transferFormat: TransferFormat = .text
    private var websocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var onReceive: OnReceiveHandler?
    private var onClose: OnCloseHander?
    private var receiveTask: Task<Void, Never>?

    init(accessTokenFactory: (@Sendable () async throws -> String?)?,
         logger: Logger,
         logMessageContent: Bool,
         headers: [String: String],
         urlSession: URLSession? = nil) {
        self.accessTokenFactory = accessTokenFactory
        self.logger = logger
        self.logMessageContent = logMessageContent
        self.headers = headers
        self.urlSession = urlSession
    }

    func onReceive(_ handler: OnReceiveHandler?) {
        self.onReceive = handler
    }

    func onClose(_ handler: OnCloseHander?) {
        self.onClose = handler
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        self.logger.log(level: .debug, message: "(WebSockets transport) Connecting.")

        self.urlSession = self.urlSession ?? URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        self.transferFormat = transferFormat

        var urlComponents = URLComponents(url: URL(string: url)!, resolvingAgainstBaseURL: false)!

        if urlComponents.scheme == "http" {
            urlComponents.scheme = "ws"
        } else if urlComponents.scheme == "https" {
            urlComponents.scheme = "wss"
        }

        var request = URLRequest(url: urlComponents.url!)
        
        // Add token to query
        if accessTokenFactory != nil {
            let token = try await accessTokenFactory!()
            urlComponents.queryItems = [URLQueryItem(name: "access_token", value: token)]
        }

        // Add headeres
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        websocket = urlSession!.webSocketTask(with: URL(string: urlComponents.string!)!)

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
        try await openTcs.task();
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

    func stop(error: Error?) async throws {
        // trigger once?
        if await stopped.compareExchange(expected: false, desired: true) != false {
            return
        }

        receiveTask?.cancel()
        websocket?.cancel()
        urlSession?.finishTasksAndInvalidate()
        await receiveTask?.value
        await onClose?(nil)
    }

    // When connection close by any reasion?
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        logger.log(level: .debug, message: "(WebSockets transport) URLSession didCompleteWithError: \(String(describing: error))")

        Task {
            if await openTcs.trySetResult(.failure(error ?? SignalRError.connectionAborted)) == true {
                logger.log(level: .debug, message: "(WebSockets transport) WebSocket connection closed")
            } else {
                try await stop(error: error)
            }
        }
    }

    // When receive websocket close message?
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        logger.log(level: .debug, message: "(WebSockets transport) URLSession didCloseWith: \(closeCode)")

        Task {
            if await openTcs.trySetResult(.failure(SignalRError.connectionAborted)) == true {
                logger.log(level: .debug, message: "(WebSockets transport) WebSocket connection with code \(closeCode))")
            } else {
                try await stop(error: nil)
            }
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        logger.log(level: .debug, message: "(WebSockets transport) urlSession didOpenWithProtocol invoked. WebSocket open")

        Task {
            if await openTcs.trySetResult(.success(())) == true {
                logger.log(level: .debug, message: "(WebSockets transport) WebSocket connected")
            }
        }
    }

    private func receiveMessage() async {
        guard let websocket = websocket else {
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
            logger.log(level: .error, message: "Failed to receive message: \(error)")
            websocket.cancel(with: .invalid, reason: nil)
        }
    }
}