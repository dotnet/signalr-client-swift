// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

actor AtomicState<T: Equatable> {
    init(initialState: T) {
        self.state = initialState
    }
    private var state: T

    func compareExchange(expected: T, desired: T) -> T {
        let origin = state 
        if (expected == state) {
            state = desired
        }
        return origin
    }
}