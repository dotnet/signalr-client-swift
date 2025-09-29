@testable import SignalRClient
import XCTest

// Remove all ping messages from the message array but keep the first one.
func removeAllPingMessagesButFirst(messages: [HubMessage]) -> [HubMessage] {
    var result = [HubMessage]()
    var containsPing = false
    for message in messages {
        if let pingMessage = message as? PingMessage {
            if containsPing {
                continue // Skip all but the first ping message
            }
            result.append(pingMessage)
            containsPing = true
        } else {
            result.append(message)
        }
    }
    return result
}

func removeAllPingMessages(messages: [HubMessage]) -> [HubMessage] {
    var result = [HubMessage]()
    for message in messages {
        if let pingMessage = message as? PingMessage {
        } else {
            result.append(message)
        }
    }
    return result
}

func getParsedData(data: [StringOrData?], binder: InvocationBinder) throws -> [HubMessage] {
    var parsedData = [HubMessage]()
    for item in data {
        if item == nil {
            continue
        }
        let messages = try JsonHubProtocol().parseMessages(input: item!, binder: binder);
        // append the messages array as a single element
        if !messages.isEmpty {
            parsedData.append(contentsOf: messages)
        }
    }
    return parsedData
}

public enum TestError: Error {
    case TimeoutError
}

func delayUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws-> Void {
    let startTime = Date()
    
    while Date().timeIntervalSince(startTime) < timeout {
        if condition() {
            return 
        }
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }
    throw TestError.TimeoutError
}
