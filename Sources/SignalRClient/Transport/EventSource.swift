// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// A SSE client implementation compatible with SignalR server.
// Assumptions:
//   1. No BOM charactor.
//   2. Connect is only called once
// Below features are not implemented as SignalR doesn't rely on them:
//  1. Reconnect, last Id
//  2. event name, event handlers
class EventSource: NSObject, URLSessionDataDelegate {
    private let url: URL
    private let headers: [String: String]
    private let parser: EventParser
    private var openHandler: (() -> Void)?
    private var completeHandler: ((Int?, Error?) -> Void)?
    private var messageHandler: ((String) -> Void)?
    private var urlSession: URLSession?

    init(url: URL, headers: [String: String]?) {
        self.url = url
        var headers = headers ?? [:]
        headers["Accept"] = "text/event-stream"
        headers["Cache-Control"] = "no-cache"
        self.headers = headers
        self.parser = EventParser()
    }

    func connect() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = self.headers
        config.timeoutIntervalForRequest = TimeInterval.infinity
        config.timeoutIntervalForResource = TimeInterval.infinity
        self.urlSession = URLSession(
            configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession!.dataTask(with: url).resume()
    }

    func disconnect() {
        self.urlSession?.invalidateAndCancel()
    }

    func onOpen(openHandler: @escaping (() -> Void)) {
        self.openHandler = openHandler
    }

    func onComplete(
        completionHandler: @escaping (Int?, Error?) -> Void
    ) {
        self.completeHandler = completionHandler
    }

    func onMessage(messageHandler: @escaping (String) -> Void) {
        self.messageHandler = messageHandler
    }

    // MARK: redirect
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var newRequest = request
        self.headers.forEach { key, value in
            newRequest.setValue(value, forHTTPHeaderField: key)
        }
        completionHandler(newRequest)
    }

    // MARK: open
    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition)
            -> Void
    ) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        if statusCode == 200 {
            self.openHandler?()
        }
        // forward anyway
        completionHandler(URLSession.ResponseDisposition.allow)
    }

    // MARK: data
    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        parser.Parse(data: data).forEach { event in
            self.messageHandler?(event)
        }
    }

    // MARK: complete
    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        self.completeHandler?(statusCode, error)
    }
}

// The parser supports both "\n" and "\r\n" as field separator. "\r" is rarely used practically thus not supported for simplicity.
// Comments and fields other than "data" are silently dropped.
class EventParser {
    static let cr = Character("\r").asciiValue!
    static let ln = Character("\n").asciiValue!
    static let dot = Character(":").asciiValue!
    static let space = Character(" ").asciiValue!
    static let data = "data".data(using: .utf8)!

    private var lines: [String]
    private var buffer: Data

    init() {
        self.lines = []
        self.buffer = Data()
    }

    func Parse(data: Data) -> [String] {
        var events: [String] = []
        var data = data
        while let index = data.firstIndex(of: EventParser.ln) {
            var segment = data[..<index]
            data = data[(index + 1)...]

            if segment.last == EventParser.cr {
                segment = segment.dropLast()
            }
            buffer.append(segment)

            var line = buffer
            buffer = Data()

            if line.isEmpty {
                if lines.count > 0 {
                    events.append(lines.joined(separator: "\n"))
                    lines = []
                }
            } else {
                guard line.starts(with: EventParser.data) else {
                    continue
                }
                line = line[EventParser.data.count...]
                guard !line.isEmpty else {
                    lines.append("")
                    continue
                }
                guard line.first == EventParser.dot else {
                    continue
                }
                line = line.dropFirst()
                if line.first == EventParser.space {
                    line = line.dropFirst()
                }
                guard let line = String(data: line, encoding: .utf8) else {
                    continue
                }
                lines.append(line)
            }
        }
        buffer.append(data)

        return events
    }
}
