import Foundation
#if canImport(os)
import os
#endif

public enum LogLevel: Int {
    case debug, information, warning, error
}

public protocol LogHandler: Sendable {
    func log(
        logLevel: LogLevel, message: LogMessage, file: String, function: String,
        line: UInt)
}

// The current functionality is similar to String. It could be extended in the future.
public struct LogMessage: ExpressibleByStringInterpolation,
    CustomStringConvertible
{
    private var value: String

    public init(stringLiteral value: String) {
        self.value = value
    }

    public var description: String {
        return self.value
    }
}

struct Logger {
    private var logHandler: LogHandler
    private let logLevel: LogLevel?

    init(logLevel: LogLevel?, logHandler: LogHandler) {
        self.logLevel = logLevel
        self.logHandler = logHandler
    }

    public func log(
        level: LogLevel, message: LogMessage, file: String = #fileID,
        function: String = #function, line: UInt = #line
    ) {
        guard let minLevel = self.logLevel, level.rawValue >= minLevel.rawValue
        else {
            return
        }
        logHandler.log(
            logLevel: level, message: message, file: file,
            function: function, line: line)
    }
}

#if canImport(os)
struct OSLogHandler: LogHandler {
    var logger: os.Logger
    init() {
        self.logger = os.Logger(
            subsystem: "com.microsoft.signalr.client", category: "")
    }

    public func log(
        logLevel: LogLevel, message: LogMessage, file: String, function: String,
        line: UInt
    ) {
        logger.log(
            level: logLevel.toOSLogType(),
            "[\(Date().description(with: Locale.current), privacy: .public)] [\(String(describing:logLevel), privacy: .public)] [\(fileNameWithoutPathAndSuffix(file),privacy: .public):\(function,privacy: .public):\(line,privacy: .public)] - \(message,privacy: .public)"
        )
    }

    private func fileNameWithoutPathAndSuffix(_ file: String) -> String {
        return file.components(separatedBy: "/").last!.components(
            separatedBy: "."
        ).first!
    }
}

extension LogLevel {
    fileprivate func toOSLogType() -> OSLogType {
        switch self {
        case .debug:
            return .debug
        case .information:
            return .info
        case .warning:
            // OSLog has no warning type
            return .info
        case .error:
            return .error
        }
    }
}
#else
struct OSLogHandler: LogHandler {
    public func log(
        logLevel: LogLevel, message: LogMessage, file: String, function: String,
        line: UInt
    ) {
        print(
            "[\(Date().description(with: Locale.current))] [\(String(describing:logLevel))] [\(fileNameWithoutPathAndSuffix(file)):\(function):\(line)] - \(message)"
        )
    }

    private func fileNameWithoutPathAndSuffix(_ file: String) -> String {
        return file.components(separatedBy: "/").last!.components(
            separatedBy: "."
        ).first!
    }
}
#endif