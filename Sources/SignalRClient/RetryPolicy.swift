import Foundation

public protocol RetryPolicy: Sendable {
    // Nil means no more retry
    func nextRetryInterval(retryCount: Int) -> TimeInterval?
}

final class DefaultRetryPolicy: RetryPolicy, @unchecked Sendable {
    private let retryDelays: [TimeInterval]
    private var currentRetryCount = 0

    init(retryDelays: [TimeInterval]) {
        self.retryDelays = retryDelays
    }

    func nextRetryInterval(retryCount: Int) -> TimeInterval? {
        if retryCount < retryDelays.count {
            return retryDelays[retryCount]
        }

        return nil
    }
}