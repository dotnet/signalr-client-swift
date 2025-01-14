import Foundation
#if canImport(os)
import os
#endif

public enum LogLevel: Int, Sendable {
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

struct Logger: Sendable {
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

struct DefaultLogHandler: LogHandler {
    public func log(
        logLevel: LogLevel, message: LogMessage, file: String, function: String,
        line: UInt
    ) {
        print(
            "[\(Date().description(with: Locale.current))] [\(String(describing:logLevel))] [\(file.fileNameWithoutPathAndSuffix()):\(function):\(line)] - \(message)"
        )
    }
}

extension String {
    fileprivate func fileNameWithoutPathAndSuffix() -> String {
        return self.components(separatedBy: "/").last!.components(
            separatedBy: "."
        ).first!
    }
}
