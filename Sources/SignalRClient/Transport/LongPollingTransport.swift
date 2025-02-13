import Foundation

actor LongPollingTransport: Transport {
    let httpClient: HttpClient
    let logger: Logger
    var options: HttpConnectionOptions

    var url: String?
    var running: Bool
    var closeError: Error?
    var receiving: Task<Void, Never>?
    var onReceiveHandler: OnReceiveHandler?
    var onCloseHandler: OnCloseHander?

    init(
        httpClient: HttpClient, logger: Logger, options: HttpConnectionOptions
    ) {
        self.httpClient = httpClient
        self.options = options
        self.running = false
        self.logger = logger
    }

    func connect(url: String, transferFormat: TransferFormat) async throws {
        // MARK: Here's an assumption that the connect won't be called twice
        self.url = url
        logger.log(
            level: .debug, message: "(LongPolling transport) Connecting."
        )

        var pollRequest = HttpRequest(
            method: .GET, url: url, responseType: transferFormat,
            options: options
        )
        pollRequest.appendDateInUrl()
        logger.log(
            level: .debug,
            message: "(LongPolling transport) polling: \(pollRequest.url)."
        )

        let (_, response) = try await httpClient.send(request: pollRequest)

        if response.statusCode != 200 {
            logger.log(
                level: .error,
                message:
                "(LongPolling transport) Unexpected response code: \(response.statusCode)."
            )
            self.closeError = SignalRError.unexpectedResponseCode(
                response.statusCode)
            self.running = false
        } else {
            self.running = true
        }

        self.receiving = Task {
            await poll(pollRequest: pollRequest)
        }
    }

    func poll(pollRequest: HttpRequest) async {
        var pollRequest = pollRequest
        while running {
            do {
                pollRequest.appendDateInUrl()
                logger.log(
                    level: .debug,
                    message:
                    "(LongPolling transport) polling: \(pollRequest.url)."
                )

                let (message, response) = try await httpClient.send(
                    request: pollRequest)

                if response.statusCode == 204 {
                    logger.log(
                        level: .information,
                        message:
                        "(LongPolling transport) Poll terminated by server."
                    )
                    self.running = false
                } else if response.statusCode != 200 {
                    logger.log(
                        level: .error,
                        message:
                        "(LongPolling transport) Unexpected response code: \(response.statusCode)."
                    )
                    self.closeError = SignalRError.unexpectedResponseCode(
                        response.statusCode)
                } else {
                    if !message.isEmpty() {
                        logger.log(
                            level: .debug,
                            message:
                            "(LongPolling transport) data received. \(message.getDataDetail(includeContent: options.logMessageContent ?? false))"
                        )
                        await self.onReceiveHandler?(message)
                    } else {
                        logger.log(
                            level: .debug,
                            message:
                            "(LongPolling transport) Poll timed out, reissuing."
                        )
                    }
                }
            } catch {
                if !self.running {
                    // Log but disregard errors that occur after stopping
                    logger.log(
                        level: .debug,
                        message:
                        "(LongPolling transport) Poll errored after shutdown: \(error)"
                    )
                } else {
                    if let err = error as? SignalRError,
                       err == SignalRError.httpTimeoutError {
                        // Ignore timeouts and reissue the poll.
                        logger.log(
                            level: .debug,
                            message:
                            "(LongPolling transport) Poll timed out, reissuing."
                        )
                    } else {
                        // Close the connection with the error as the result.
                        self.closeError = error
                        self.running = false
                    }
                }
            }
        }

        logger.log(
            level: .debug, message: "(LongPolling transport) Polling complete."
        )
        if !Task.isCancelled {
            await raiseClose()
        }

    }

    func send(_ requestData: StringOrData) async throws {
        guard self.running else {
            throw SignalRError.cannotSentUntilTransportConnected
        }
        logger.log(
            level: .debug,
            message:
            "(LongPolling transport) sending data. \(requestData.getDataDetail(includeContent: options.logMessageContent ?? false))"
        )
        let request = HttpRequest(
            method: .POST, url: self.url!, content: requestData,
            options: options
        )
        let (_, response) = try await httpClient.send(request: request)
        logger.log(
            level: .debug,
            message:
            "(LongPolling transport) request complete. Response status: \(response.statusCode)."
        )
    }

    func stop(error: (any Error)?) async throws {
        logger.log(
            level: .debug, message: "(LongPolling transport) Stopping polling."
        )
        self.running = false
        self.receiving?.cancel()

        await self.receiving?.value

        logger.log(
            level: .debug,
            message:
            "(LongPolling transport) sending DELETE request to \(String(describing: self.url))"
        )

        do {
            let deleteRequest = HttpRequest(
                method: .DELETE, url: self.url!, options: options
            )
            let (_, response) = try await httpClient.send(
                request: deleteRequest)
            if response.statusCode == 404 {
                logger.log(
                    level: .debug,
                    message:
                    "(LongPolling transport) A 404 response was returned from sending a DELETE request."
                )
            } else if response.ok() {
                logger.log(
                    level: .debug,
                    message: "(LongPolling transport) DELETE request accepted."
                )
            } else {
                logger.log(
                    level: .debug,
                    message:
                    "(LongPolling transport) Unexpected response code sending a DELETE request: \(response.statusCode)"
                )
            }
        } catch {
            logger.log(
                level: .debug,
                message:
                "(LongPolling transport) Error sending a DELETE request: \(error)"
            )
        }
        logger.log(
            level: .debug, message: "(LongPolling transport) Stop finished."
        )

        await raiseClose()
    }

    func onReceive(_ handler: OnReceiveHandler?) {
        self.onReceiveHandler = handler
    }

    func onClose(_ handler: OnCloseHander?) {
        self.onCloseHandler = handler
    }

    private func raiseClose() async {
        guard let onCloseHandler = self.onCloseHandler else {
            return
        }

        logger.log(
            level: .debug,
            message:
            "(LongPolling transport) Firing onclose event.\(closeError == nil ? "" : " Error: \(closeError!)")"
        )
        await onCloseHandler(self.closeError)
    }
}

extension HttpRequest {
    mutating func appendDateInUrl() {
        if self.url.last != Character("&") {
            self.url.append("&")
        }
        self.url = self.url.components(separatedBy: "_=").first!.appending(
            "_=\(Int64((Date().timeIntervalSince1970 * 1000)))")
    }
}
