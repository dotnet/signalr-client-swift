// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

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
