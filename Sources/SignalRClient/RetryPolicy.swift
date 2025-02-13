// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

public protocol RetryPolicy: Sendable {
    // Return TimeInterval in seconds, and Nil means no more retry
    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval?
}

public struct RetryContext {
    public let retryCount: Int
    public let elapsed: TimeInterval
    public let retryReason: Error?
}

final class DefaultRetryPolicy: RetryPolicy, @unchecked Sendable {
    private let retryDelays: [TimeInterval]
    private var currentRetryCount = 0

    init(retryDelays: [TimeInterval]) {
        self.retryDelays = retryDelays
    }

    func nextRetryInterval(retryContext: RetryContext) -> TimeInterval? {
        if retryContext.retryCount < retryDelays.count {
            return retryDelays[retryContext.retryCount]
        }

        return nil
    }
}