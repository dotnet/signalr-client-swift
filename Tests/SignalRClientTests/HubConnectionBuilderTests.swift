// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest
@testable import SignalRClient

final class HubConnectionBuilderTests: XCTestCase {
    
    // MARK: - URL Configuration Tests
    
    func testWithUrl_SetsUrl() {
        let builder = HubConnectionBuilder()
        let url = "http://localhost:5000/hub"
        
        _ = builder.withUrl(url: url)
        
        XCTAssertEqual(builder.url, url)
    }
    
    func testWithUrl_WithTransport_SetsUrlAndTransport() {
        let builder = HubConnectionBuilder()
        let url = "http://localhost:5000/hub"
        let transport: HttpTransportType = .webSockets
        
        _ = builder.withUrl(url: url, transport: transport)
        
        XCTAssertEqual(builder.url, url)
        XCTAssertEqual(builder.httpConnectionOptions.transport, transport)
    }
    
    func testWithUrl_WithOptions_SetsUrlAndOptions() {
        let builder = HubConnectionBuilder()
        let url = "http://localhost:5000/hub"
        var options = HttpConnectionOptions()
        options.transport = .longPolling
        options.logLevel = .debug
        
        _ = builder.withUrl(url: url, options: options)
        
        XCTAssertEqual(builder.url, url)
        XCTAssertEqual(builder.httpConnectionOptions.transport, .longPolling)
        XCTAssertEqual(builder.httpConnectionOptions.logLevel, .debug)
    }
    
    // MARK: - Log Level Tests
    
    func testWithLogLevel_SetsLogLevel() {
        let builder = HubConnectionBuilder()
        let logLevel: LogLevel = .debug
        
        _ = builder.withLogLevel(logLevel: logLevel)
        
        XCTAssertEqual(builder.logLevel, logLevel)
        XCTAssertEqual(builder.httpConnectionOptions.logLevel, logLevel)
    }
    
    func testWithLogLevel_UpdatesExistingLogLevel() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withLogLevel(logLevel: .debug)
        XCTAssertEqual(builder.logLevel, .debug)
        
        _ = builder.withLogLevel(logLevel: .error)
        XCTAssertEqual(builder.logLevel, .error)
        XCTAssertEqual(builder.httpConnectionOptions.logLevel, .error)
    }
    
    // MARK: - Log Handler Tests
    
    func testWithLogHandler_SetsLogHandler() {
        let builder = HubConnectionBuilder()
        let logHandler = TestLogHandler()
        
        _ = builder.withLogHandler(logHandler: logHandler)
        
        XCTAssertNotNil(builder.logHandler)
    }
    
    // MARK: - Hub Protocol Tests
    
    func testWithHubProtocol_JsonWithDefaults_SetsJsonHubProtocol() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withHubProtocol(hubProtocol: .json())
        
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertTrue(builder.hubProtocol is JsonHubProtocol)
        
        if let jsonProtocol = builder.hubProtocol as? JsonHubProtocol {
            XCTAssertEqual(jsonProtocol.name, "json")
            XCTAssertEqual(jsonProtocol.version, 2)
        }
    }
    
    func testWithHubProtocol_JsonWithCustomEncoder_SetsJsonHubProtocol() {
        let builder = HubConnectionBuilder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        
        _ = builder.withHubProtocol(hubProtocol: .json(encoder))
        
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertTrue(builder.hubProtocol is JsonHubProtocol)
        
        if let jsonProtocol = builder.hubProtocol as? JsonHubProtocol {
            XCTAssertTrue(jsonProtocol.encoder === encoder)
        }
    }
    
    func testWithHubProtocol_JsonWithCustomDecoder_SetsJsonHubProtocol() {
        let builder = HubConnectionBuilder()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        _ = builder.withHubProtocol(hubProtocol: .json(.init(), decoder))
        
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertTrue(builder.hubProtocol is JsonHubProtocol)
        
        if let jsonProtocol = builder.hubProtocol as? JsonHubProtocol {
            XCTAssertTrue(jsonProtocol.decoder === decoder)
        }
    }
    
    func testWithHubProtocol_JsonWithCustomEncoderAndDecoder_SetsJsonHubProtocol() {
        let builder = HubConnectionBuilder()
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        _ = builder.withHubProtocol(hubProtocol: .json(encoder, decoder))
        
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertTrue(builder.hubProtocol is JsonHubProtocol)
        
        if let jsonProtocol = builder.hubProtocol as? JsonHubProtocol {
            XCTAssertTrue(jsonProtocol.encoder === encoder)
            XCTAssertTrue(jsonProtocol.decoder === decoder)
        }
    }
    
    func testWithHubProtocol_MessagePack_SetsMessagePackHubProtocol() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withHubProtocol(hubProtocol: .messagePack)
        
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertTrue(builder.hubProtocol is MessagePackHubProtocol)
    }
    
    // MARK: - Server Timeout Tests
    
    func testWithServerTimeout_SetsServerTimeout() {
        let builder = HubConnectionBuilder()
        let timeout: TimeInterval = 45.0
        
        _ = builder.withServerTimeout(serverTimeout: timeout)
        
        XCTAssertEqual(builder.serverTimeout, timeout)
    }
    
    func testWithServerTimeout_UpdatesExistingTimeout() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withServerTimeout(serverTimeout: 30.0)
        XCTAssertEqual(builder.serverTimeout, 30.0)
        
        _ = builder.withServerTimeout(serverTimeout: 60.0)
        XCTAssertEqual(builder.serverTimeout, 60.0)
    }
    
    // MARK: - Keep Alive Interval Tests
    
    func testWithKeepAliveInterval_SetsKeepAliveInterval() {
        let builder = HubConnectionBuilder()
        let interval: TimeInterval = 20.0
        
        _ = builder.withKeepAliveInterval(keepAliveInterval: interval)
        
        XCTAssertEqual(builder.keepAliveInterval, interval)
    }
    
    func testWithKeepAliveInterval_UpdatesExistingInterval() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withKeepAliveInterval(keepAliveInterval: 10.0)
        XCTAssertEqual(builder.keepAliveInterval, 10.0)
        
        _ = builder.withKeepAliveInterval(keepAliveInterval: 25.0)
        XCTAssertEqual(builder.keepAliveInterval, 25.0)
    }
    
    // MARK: - Automatic Reconnect Tests
    
    func testWithAutomaticReconnect_DefaultRetryPolicy_SetsRetryPolicy() {
        let builder = HubConnectionBuilder()
        
        _ = builder.withAutomaticReconnect()
        
        XCTAssertNotNil(builder.retryPolicy)
        XCTAssertTrue(builder.retryPolicy is DefaultRetryPolicy)
    }
    
    func testWithAutomaticReconnect_CustomRetryPolicy_SetsRetryPolicy() {
        let builder = HubConnectionBuilder()
        let customPolicy = TestRetryPolicy()
        
        _ = builder.withAutomaticReconnect(retryPolicy: customPolicy)
        
        XCTAssertNotNil(builder.retryPolicy)
        XCTAssertTrue(builder.retryPolicy is TestRetryPolicy)
    }
    
    func testWithAutomaticReconnect_CustomRetryDelays_SetsRetryPolicy() {
        let builder = HubConnectionBuilder()
        let delays: [TimeInterval] = [1, 5, 10, 20]
        
        _ = builder.withAutomaticReconnect(retryDelays: delays)
        
        XCTAssertNotNil(builder.retryPolicy)
        XCTAssertTrue(builder.retryPolicy is DefaultRetryPolicy)
    }
    
    // MARK: - Stateful Reconnect Tests
    
    func testWithStatefulReconnect_SetsBufferSizeAndFlag() {
        let builder = HubConnectionBuilder()
        let bufferSize = 50_000_000
        
        _ = builder.withStatefulReconnect(bufferSize: bufferSize)
        
        XCTAssertEqual(builder.statefulReconnectBufferSize, bufferSize)
        XCTAssertEqual(builder.httpConnectionOptions.useStatefulReconnect, true)
    }
    
    // MARK: - Builder Method Chaining Tests
    
    func testBuilderMethodChaining_ReturnsBuilder() {
        let builder = HubConnectionBuilder()
        
        let result = builder
            .withUrl(url: "http://localhost:5000/hub")
            .withLogLevel(logLevel: .debug)
            .withHubProtocol(hubProtocol: .json())
            .withServerTimeout(serverTimeout: 30)
            .withKeepAliveInterval(keepAliveInterval: 15)
            .withAutomaticReconnect()
        
        XCTAssertTrue(result === builder)
    }
    
    func testBuilderMethodChaining_OrderIndependent() {
        let url = "http://localhost:5000/hub"
        let logLevel: LogLevel = .information
        let timeout: TimeInterval = 40.0
        let interval: TimeInterval = 20.0
        
        let builder1 = HubConnectionBuilder()
            .withUrl(url: url)
            .withLogLevel(logLevel: logLevel)
            .withServerTimeout(serverTimeout: timeout)
            .withKeepAliveInterval(keepAliveInterval: interval)
        
        let builder2 = HubConnectionBuilder()
            .withKeepAliveInterval(keepAliveInterval: interval)
            .withServerTimeout(serverTimeout: timeout)
            .withLogLevel(logLevel: logLevel)
            .withUrl(url: url)
        
        XCTAssertEqual(builder1.url, builder2.url)
        XCTAssertEqual(builder1.logLevel, builder2.logLevel)
        XCTAssertEqual(builder1.serverTimeout, builder2.serverTimeout)
        XCTAssertEqual(builder1.keepAliveInterval, builder2.keepAliveInterval)
    }
    
    // MARK: - Build Tests
    
    func testBuild_WithMinimalConfiguration_ReturnsHubConnection() {
        let builder = HubConnectionBuilder()
        
        let connection = builder.withUrl(url: "http://localhost:5000/hub").build()
        
        XCTAssertNotNil(connection)
    }
    
    func testBuild_WithAllOptions_ReturnsHubConnection() {
        let builder = HubConnectionBuilder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let connection = builder
            .withUrl(url: "http://localhost:5000/hub")
            .withHubProtocol(hubProtocol: .json(encoder, decoder))
            .withLogLevel(logLevel: .debug)
            .withServerTimeout(serverTimeout: 30)
            .withKeepAliveInterval(keepAliveInterval: 15)
            .withAutomaticReconnect(retryDelays: [0, 2, 10, 30])
            .withStatefulReconnect(bufferSize: 100_000_000)
            .build()
        
        XCTAssertNotNil(connection)
    }
    
    func testBuild_WithoutUrl_Crashes() {
        // This should trigger a fatal error: fatalError("url must be set with .withUrl(String:)")
        // We can't easily test fatal errors in XCTest, but we document the expected behavior
        // If you call HubConnectionBuilder().build() without setting a URL, it will crash
    }
    
    func testBuild_UsesDefaultsForUnsetValues() {
        let builder = HubConnectionBuilder()
        
        // Only set URL, everything else should use defaults
        _ = builder.withUrl(url: "http://localhost:5000/hub")
        
        // Verify internal state before build
        XCTAssertNil(builder.hubProtocol) // Will default to JsonHubProtocol in build()
        XCTAssertNil(builder.logLevel)
        XCTAssertNil(builder.logHandler)
        XCTAssertNil(builder.serverTimeout) // Will use default in HubConnection
        XCTAssertNil(builder.keepAliveInterval) // Will use default in HubConnection
        XCTAssertNil(builder.retryPolicy) // Will default to no-retry policy in build()
        XCTAssertNil(builder.statefulReconnectBufferSize)
        
        let connection = builder.build()
        XCTAssertNotNil(connection)
    }
    
    func testBuild_MultipleTimes_CreatesNewConnections() {
        let builder = HubConnectionBuilder().withUrl(url: "http://localhost:5000/hub")
        
        let connection1 = builder.build()
        let connection2 = builder.build()
        
        // Both connections should be created successfully
        XCTAssertNotNil(connection1)
        XCTAssertNotNil(connection2)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteConfiguration_AllPropertiesSet() {
        let builder = HubConnectionBuilder()
        let url = "http://localhost:5000/hub"
        let logLevel: LogLevel = .warning
        let timeout: TimeInterval = 50.0
        let interval: TimeInterval = 25.0
        let bufferSize = 75_000_000
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        _ = builder
            .withUrl(url: url)
            .withLogLevel(logLevel: logLevel)
            .withHubProtocol(hubProtocol: .json(encoder, decoder))
            .withServerTimeout(serverTimeout: timeout)
            .withKeepAliveInterval(keepAliveInterval: interval)
            .withAutomaticReconnect(retryDelays: [1, 2, 3])
            .withStatefulReconnect(bufferSize: bufferSize)
        
        XCTAssertEqual(builder.url, url)
        XCTAssertEqual(builder.logLevel, logLevel)
        XCTAssertNotNil(builder.hubProtocol)
        XCTAssertEqual(builder.serverTimeout, timeout)
        XCTAssertEqual(builder.keepAliveInterval, interval)
        XCTAssertNotNil(builder.retryPolicy)
        XCTAssertEqual(builder.statefulReconnectBufferSize, bufferSize)
        XCTAssertEqual(builder.httpConnectionOptions.useStatefulReconnect, true)
        
        let connection = builder.build()
        XCTAssertNotNil(connection)
    }
}

// MARK: - Test Helpers

final class TestLogHandler: LogHandler {
    func log(logLevel: LogLevel, message: LogMessage, file: String, function: String, line: UInt) {
        // No-op for testing
    }
}

final class TestRetryPolicy: RetryPolicy {
    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval? {
        return nil
    }
}
