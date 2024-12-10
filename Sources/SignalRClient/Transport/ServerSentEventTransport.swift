#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
import EventSource
import Foundation

actor ServerSentEventTransport: Transport {
    let httpClient: HttpClient
    let logger: Logger
    let accessToken: String?
    var options: HttpConnectionOptions

    var url: String?
    var closeError: Error?
    var receiving: Task<Void, Never>?
    var receiveHandler: OnReceiveHandler?
    var closeHandler: OnCloseHander?
    var eventSource: EventSourceAdaptor?

    init(
        httpClient: HttpClient, accessToken: String?, logger: Logger,
        options: HttpConnectionOptions
    ) {
        self.httpClient = httpClient
        self.options = options
        self.accessToken = accessToken
        self.logger = logger
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        // MARK: Here's an assumption that the connect won't be called twice
        guard transferFormat == .text else {
            throw SignalRError.eventSourceInvalidTransferFormat
        }

        logger.log(
            level: .debug, message: "(SSE transport) Connecting.")

        self.url = url
        var url = url
        if let accessToken = self.accessToken {
            url =
                "\(url)\(url.contains("?") ? "&" : "?")access_token=\(accessToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }

        let eventSource = options.eventSource ?? DefaultEventSourceAdaptor(logger: logger)

        await eventSource.onClose(closeHandler: self.close)

        await eventSource.onMessage { data in
            let message = StringOrData.string(data)
            self.logger.log(
                level: .debug,
                message:
                    "(SSE) data received. \(message.getDataDetail(includeContent: self.options.logMessageContent ?? false))"
            )
            await self.receiveHandler?(message)
        }

        try await eventSource.start(url: url, options: options)

        self.eventSource = eventSource
        logger.log(
            level: .information, message: "SSE connected to \(self.url!)")
    }

    func send(_ requestData: StringOrData) async throws {
        guard self.eventSource != nil else {
            throw SignalRError.cannotSentUntilTransportConnected
        }
        logger.log(
            level: .debug,
            message:
                "(SSE transport) sending data. \(requestData.getDataDetail(includeContent: options.logMessageContent ?? false))"
        )
        let request = HttpRequest(
            method: .POST, url: self.url!, content: requestData,
            options: options)
        let (_, response) = try await httpClient.send(request: request)
        logger.log(
            level: .debug,
            message:
                "(SSE transport) request complete. Response status: \(response.statusCode)."
        )
    }

    func stop(error: (any Error)?) async throws {
        await self.close(err: error)
    }

    func onReceive(_ handler: OnReceiveHandler?) {
        self.receiveHandler = handler
    }

    func onClose(_ handler: OnCloseHander?) {
        self.closeHandler = handler
    }

    private func close(err: Error?) async {
        guard let eventSource = self.eventSource else {
            return
        }
        self.eventSource = nil
        await eventSource.stop(err: err)
        await closeHandler?(err)
    }
}

final class DefaultEventSourceAdaptor: EventSourceAdaptor, @unchecked Sendable {
    private let logger: Logger
    private var closeHandler: ((Error?) async -> Void)?
    private var messageHandler: ((String) async -> Void)?

    private var eventSource: EventSource?
    private var dispatchQueue: DispatchQueue
    private var messageTask: Task<Void, Never>?
    private var messageStream: AsyncStream<String>?

    init(logger: Logger) {
        self.logger = logger
        self.dispatchQueue = DispatchQueue(label: "DefaultEventSourceAdaptor")
    }

    func start(url: String, headers: [String: String]) async throws {
        guard let url = URL(string: url) else {
            throw SignalRError.invalidUrl(url)
        }
        let eventSource = EventSource(url: url, headers: headers)
        let openTcs = TaskCompletionSource<Void>()

        eventSource.onOpen {
            // This will be triggered when a non 2XX code is returned. The spec doesn't define this behaviour. So it's implementation specific.
            Task {
                _ = await openTcs.trySetResult(.success(()))
                self.eventSource = eventSource
            }
        }
        
        messageStream = AsyncStream{ continuation in
            eventSource.onComplete { statusCode, _, err in
                Task {
                    let connectFail = await openTcs.trySetResult(
                        .failure(SignalRError.eventSourceFailedToConnect))
                    self.logger.log(
                        level: .debug,
                        message:
                            "(Event Source) \(connectFail ? "Failed to open.": "Disconnected.").\(statusCode == nil ? "" : " StatusCode: \(statusCode!).") \(err == nil ? "": " Error: \(err!).")"
                    )
                    continuation.finish()
                    await self.close(err: err)
                }
            }
            
            eventSource.onMessage { _, _, data in
                guard let data = data else {
                    return
                }
                continuation.yield(data)
            }
        }

        eventSource.connect()
        try await openTcs.task()

        messageTask = Task {
            for await message in messageStream! {
                await self.messageHandler?(message)
            }
        }
    }

    func stop(err: Error?) async {
        await self.close(err: err)
    }

    func onClose(closeHandler: @escaping (Error?) async -> Void) async {
        self.closeHandler = closeHandler
    }

    func onMessage(messageHandler: @escaping (String) async -> Void) async {
        self.messageHandler = messageHandler
    }

    private func close(err: Error?) async {
        var eventSource: EventSource?
        dispatchQueue.sync {
            eventSource = self.eventSource
            self.eventSource = nil
        }
        guard let eventSource = eventSource else {
            return
        }
        eventSource.disconnect()
        await messageTask?.value
        await self.closeHandler?(err)
    }
}

extension EventSourceAdaptor {
    fileprivate func start(
        url: String, headers: [String: String] = [:],
        options: HttpConnectionOptions,
        includeUserAgent: Bool = true
    ) async throws {
        var headers = headers
        if includeUserAgent {
            headers["User-Agent"] = Utils.getUserAgent()
        }
        if let optionHeaders = options.headers {
            headers = headers.merging(optionHeaders) { (_, new) in new }
        }
        try await start(url: url, headers: headers)
    }
}
#endif

public protocol EventSourceAdaptor: Sendable {
    func start(url: String, headers: [String: String]) async throws
    func stop(err: Error?) async
    func onClose(closeHandler: @escaping (Error?) async -> Void) async
    func onMessage(messageHandler: @escaping (String) async -> Void) async
}