import XCTest

@testable import SignalRClient

final class MockLogHandler: LogHandler, @unchecked Sendable {
    private let queue: DispatchQueue
    private let innerLogHandler: LogHandler?
    private var logs: [String]

    // set showLog to true for debug
    init(showLog: Bool = false) {
        queue = DispatchQueue(label: "MockLogHandler")
        logs = []
        innerLogHandler = showLog ? OSLogHandler() : nil
    }

    func log(
        logLevel: SignalRClient.LogLevel, message: SignalRClient.LogMessage,
        file: String, function: String, line: UInt
    ) {
        queue.sync {
            logs.append("\(message)")
        }
        innerLogHandler?.log(
            logLevel: logLevel, message: message, file: file,
            function: function, line: line)
    }

}

extension MockLogHandler {
    func clear() {
        queue.sync {
            logs.removeAll()
        }
    }

    func verifyLogged(
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        queue.sync {
            for log in logs {
                if log.contains(message) {
                    return
                }
            }
            XCTFail(
                "Expected log not found: \"\(message)\"", file: file, line: line
            )
        }
    }

    func verifyNotLogged(
        _ message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        queue.sync {
            for log in logs {
                if log.contains(message) {
                    XCTFail(
                        "Unexpected Log found: \"\(message)\"", file: file,
                        line: line)
                }
            }
        }
    }
}

class LoggerTests: XCTestCase {
    func testOSLogHandler() {
        let logger = Logger(logLevel: .debug, logHandler: OSLogHandler())
        logger.log(level: .debug, message: "Hello world")
        logger.log(level: .information, message: "Hello world \(true)")
    }

    func testMockHandler() {
        let mockLogHandler = MockLogHandler()
        let logger = Logger(logLevel: .information, logHandler: mockLogHandler)
        logger.log(level: .error, message: "error")
        logger.log(level: .information, message: "info")
        logger.log(level: .debug, message: "debug")
        mockLogHandler.verifyLogged("error")
        mockLogHandler.verifyLogged("info")
        mockLogHandler.verifyNotLogged("debug")
        mockLogHandler.clear()
        mockLogHandler.verifyNotLogged("error")
        mockLogHandler.verifyNotLogged("info")
    }
}
