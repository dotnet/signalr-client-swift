// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest

@testable import SignalRClient

class LongPollingTransportTests: XCTestCase {
    // MARK: poll
    func testPollCancelled() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.onClose { err in }
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string("poll-result"),
                HttpResponse(statusCode: 200)
            )
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("data received")
        logHandler.verifyLogged("poll-result")
        logHandler.verifyNotLogged("complete")
        t.cancel()
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("complete")
        await t.value
        logHandler.verifyNotLogged("onclose event")
    }

    func testPollStopRunning() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.onClose { err in }
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string("poll-result"),
                HttpResponse(statusCode: 200)
            )
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("data received")
        logHandler.verifyLogged("poll-result")
        logHandler.verifyNotLogged("complete")
        await lpt.SetRunning(running: false)
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("complete")
        await t.value
        logHandler.verifyLogged("onclose event")
    }

    func testPollTerminatedWith204() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string("poll-result"),
                HttpResponse(statusCode: 204)
            )
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("terminated")
        logHandler.verifyNotLogged("data received")
        logHandler.verifyNotLogged("poll-result")
        logHandler.verifyLogged("complete")
        await t.value
    }

    func testPollUnexpectedStatusCode() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string("poll-result"),
                HttpResponse(statusCode: 222)
            )
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyNotLogged("data received")
        logHandler.verifyNotLogged("poll-result")
        logHandler.verifyNotLogged("complete")
        let err = await lpt.closeError as? SignalRError
        XCTAssertEqual(err, SignalRError.unexpectedResponseCode(222))
        t.cancel()
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("complete")
        await t.value
    }

    func testPollTimeoutWithEmptyMessage() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (StringOrData.string(""), HttpResponse(statusCode: 200))
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("timed out")
        logHandler.verifyNotLogged("data received")
        logHandler.verifyNotLogged("complete")
        t.cancel()
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("complete")
        await t.value
    }

    func testPollHttpTimeout() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            throw SignalRError.httpTimeoutError
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("timed out")
        logHandler.verifyNotLogged("data received")
        logHandler.verifyNotLogged("complete")
        t.cancel()
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("complete")
        await t.value
    }

    func testPollUnknownException() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        let request = HttpRequest(
            mockId: "poll", method: .GET, url: "http://signalr.com/hub/chat")
        await client.mock(mockId: "poll") { request in
            throw SignalRError.invalidDataType
        }
        let t = Task {
            await lpt.poll(pollRequest: request)
        }
        try await Task.sleep(for: .milliseconds(300))
        logHandler.verifyLogged("polling")
        logHandler.verifyLogged("complete")
        let err = await lpt.closeError as? SignalRError
        XCTAssertEqual(err, SignalRError.invalidDataType)
        let running = await lpt.running
        XCTAssertEqual(running, false)
        await t.value
    }

    // MARK: send
    func testSend() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        let options = HttpConnectionOptions()
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        await lpt.SetUrl(url: "http://abc")
        await client.mock(mockId: "string") { request in
            XCTAssertEqual(request.content, StringOrData.string("stringbody"))
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 200)
            )
        }
        await lpt.SetMockId(mockId: "string")
        try await lpt.send(.string("stringbody"))
        logHandler.verifyLogged("200")
    }

    // MARK: stop
    func testStop() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        let options = HttpConnectionOptions()
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.SetRunning(running: true)
        await lpt.SetUrl(url: "http://abc")
        await client.mock(mockId: "stop200") { request in
            XCTAssertEqual(request.method, .DELETE)
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 200)
            )
        }
        await client.mock(mockId: "stop404") { request in
            XCTAssertEqual(request.method, .DELETE)
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 404)
            )
        }

        await client.mock(mockId: "stop300") { request in
            XCTAssertEqual(request.method, .DELETE)
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 300)
            )
        }

        await lpt.SetMockId(mockId: "stop200")
        try await lpt.stop(error: nil)
        logHandler.verifyLogged("accepted")

        logHandler.clear()
        await lpt.SetMockId(mockId: "stop404")
        try await lpt.stop(error: nil)
        logHandler.verifyLogged("404")

        logHandler.clear()
        await lpt.SetMockId(mockId: "stop300")
        try await lpt.stop(error: nil)
        logHandler.verifyLogged("Unexpected")
    }

    // MARK: connect
    func testConnect() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.onClose { err in }
        await client.mock(mockId: "connect") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 200)
            )
        }
        await lpt.SetMockId(mockId: "connect")
        try await lpt.connect(url: "url", transferFormat: .text)
        try await Task.sleep(for: .milliseconds(300))

        let running = await lpt.running
        XCTAssertTrue(running)
        await lpt.SetRunning(running: false)
    }

    func testConnectFail() async throws {
        let client = MockHttpClient()
        let logHandler = MockLogHandler()
        let logger = Logger(logLevel: .debug, logHandler: logHandler)
        var options = HttpConnectionOptions()
        options.logMessageContent = true
        let lpt = LongPollingTransport(
            httpClient: client, logger: logger, options: options)
        await lpt.onClose { err in }
        await client.mock(mockId: "connect") { request in
            try await Task.sleep(for: .milliseconds(100))
            return (
                StringOrData.string(""),
                HttpResponse(statusCode: 404)
            )
        }
        await lpt.SetMockId(mockId: "connect")
        try await lpt.connect(url: "url", transferFormat: .text)
        try await Task.sleep(for: .milliseconds(300))

        let running = await lpt.running
        XCTAssertFalse(running)
    }
    
    func testHttpRequestAppendDate() async throws{
        var request = HttpRequest(method: .DELETE, url: "http://abc", content: .string(""), responseType: .binary, headers: nil, timeout: nil)
        request.appendDateInUrl()
        XCTAssertEqual(request.url.components(separatedBy: "&").count,2)
        request.appendDateInUrl()
        XCTAssertEqual(request.url.components(separatedBy: "&").count,2)
    }
}

extension LongPollingTransport {
    fileprivate func SetRunning(running: Bool) {
        self.running = running
    }

    fileprivate func SetUrl(url: String) {
        self.url = url
    }

    fileprivate func SetMockId(mockId: String) {
        if self.options.headers == nil {
            self.options.headers = [:]
        }
        self.options.headers![mockKey] = mockId
    }
}
