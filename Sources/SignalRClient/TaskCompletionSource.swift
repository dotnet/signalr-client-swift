// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

actor TaskCompletionSource<T> {
    private var continuation: CheckedContinuation<(), Never>?
    private var result: Result<T, Error>?

    func task() async throws -> T {
        if result == nil {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return try result!.get()
    }

    func trySetResult(_ result: Result<T, Error>) -> Bool {
        if self.result == nil {
            self.result = result
            continuation?.resume()
            return true
        }
        return false
    }
}
