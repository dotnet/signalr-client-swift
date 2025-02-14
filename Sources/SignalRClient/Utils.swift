import Foundation

class Utils {
    static func getUserAgent() -> String {
        return
            "Microsoft SignalR Client/Swift \(PackageVersion); \(currentOSVersion())"
    }

    static func currentOSVersion() -> String {
        #if os(macOS)
            let osName = "macOS"
        #elseif os(iOS)
            #if targetEnvironment(macCatalyst)
                let osName = "Mac Catalyst"
            #else
                let osName = "iOS"
            #endif
        #elseif os(tvOS)
            let osName = "tvOS"
        #elseif os(watchOS)
            let osName = "watchOS"
        #elseif os(Windows)
            return "Windows"
        #elseif os(Linux)
            return "Linux"
        #else
            return "Unknown OS"
        #endif

        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString =
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            return "\(osName) \(versionString)"
        #endif
    }
}

extension HttpRequest {
    init(
        method: HttpMethod, url: String, content: StringOrData? = nil,
        responseType: TransferFormat? = nil,
        headers: [String: String]? = nil, timeout: TimeInterval? = nil,
        options: HttpConnectionOptions, includeUserAgent: Bool = true
    ) {
        self.init(
            method: method, url: url, content: content,
            responseType: responseType, headers: headers,
            timeout: timeout
        )
        if includeUserAgent {
            self.headers["User-Agent"] = Utils.getUserAgent()
        }
        if let headers = options.headers {
            self.headers = self.headers.merging(headers) { (_, new) in new }
        }
        if let timeout = options.timeout {
            self.timeout = timeout
        }
    }
}

extension Data {
    func convertToStringOrData(transferFormat: TransferFormat) throws
    -> StringOrData {
        switch transferFormat {
        case .text:
            guard
                let message = String(
                    data: self, encoding: .utf8
                )
            else {
                throw SignalRError.invalidTextMessageEncoding
            }
            return .string(message)
        case .binary:
            return .data(self)
        }
    }
}

extension StringOrData {
    func getDataDetail(includeContent: Bool) -> String {
        switch self {
        case .string(let str):
            return
                "String data of length \(str.count)\(includeContent ? ". Content: \(str)" : "")"
        case .data(let data):
            // TODO: data format?
            return
                "Binary data of length \(data.count)\(includeContent ? ". Content: \(data)" : "")"
        }
    }

    func isEmpty() -> Bool {
        switch self {
        case .string(let str):
            return str.count == 0
        case .data(let data):
            return data.isEmpty
        }
    }

    func convertToString() -> String? {
        switch self {
        case .string(let str):
            return str
        case .data(let data):
            return String(data: data, encoding: .utf8)
        }
    }

    func converToData() -> Data {
        switch self {
        case .string(let str):
            return str.data(using: .utf8)!
        case .data(let data):
            return data
        }
    }
}
