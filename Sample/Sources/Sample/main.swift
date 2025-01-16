import SignalRClient
import Foundation

print("Using SignalRClient")

struct CustomRetryPolicy: RetryPolicy {
    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval? {
        return 1
    }
}

let client = HubConnectionBuilder().withUrl(url: String("http://localhost:8080/Chat")).build()
try await client.start()

print("After start")
