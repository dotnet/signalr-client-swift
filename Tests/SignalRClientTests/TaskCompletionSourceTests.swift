// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest

@testable import SignalRClient

class TaskCompletionSourceTests: XCTestCase {
    func testSetVarAfterWait() async throws {
        let tcs = TaskCompletionSource<Bool>()
        let t = Task {
            try await Task.sleep(for: .seconds(1))
            let set = await tcs.trySetResult(.success(true))
            XCTAssertTrue(set)
        }
        let start = Date()
        let value = try await tcs.task()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(value)
        XCTAssertLessThan(abs(elapsed - 1), 0.5)
        try await t.value
    }

    func testSetVarBeforeWait() async throws {
        let tcs = TaskCompletionSource<Bool>()
        let set = await tcs.trySetResult(.success(true))
        XCTAssertTrue(set)
        let start = Date()
        let value = try await tcs.task()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(value)
        XCTAssertLessThan(elapsed, 0.1)
    }

    func testSetException() async throws {
        let tcs = TaskCompletionSource<Bool>()
        let t = Task {
            try await Task.sleep(for: .seconds(1))
            let set = await tcs.trySetResult(
                .failure(SignalRError.noHandshakeMessageReceived))
            XCTAssertTrue(set)
        }
        let start = Date()
        do {
            _ = try await tcs.task()
        } catch {
            XCTAssertEqual(
                error as? SignalRError, SignalRError.noHandshakeMessageReceived
            )
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(abs(elapsed - 1), 0.5)
        try await t.value
    }

    func testMultiSetAndMultiWait() async throws {
        let tcs = TaskCompletionSource<Bool>()

        let t = Task {
            try await Task.sleep(for: .seconds(1))
            var set = await tcs.trySetResult(.success(true))
            XCTAssertTrue(set)
            set = await tcs.trySetResult(.success(false))
            XCTAssertFalse(set)
        }

        let start = Date()
        let value = try await tcs.task()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertTrue(value)
        XCTAssertLessThan(abs(elapsed - 1), 0.5)

        let start2 = Date()
        let value2 = try await tcs.task()
        let elapsed2 = Date().timeIntervalSince(start2)
        XCTAssertTrue(value2)
        XCTAssertLessThan(elapsed2, 0.1)

        try await t.value
    }

    func testBench() async {
        let total = 10000
        var tcss: [TaskCompletionSource<Void>] = []
        tcss.reserveCapacity(total)
        for _ in 1 ... total {
            tcss.append(TaskCompletionSource<Void>())
        }
        let start = Date()
        let expectation = expectation(description: "Tcss should all complete")
        let counter = Counter(value: 0)
        for tcs in tcss {
            Task {
                try await Task.sleep(for: .microseconds(10))
                try await tcs.task()
                let c = await counter.increase(delta: 1)
                if c == total {
                    expectation.fulfill()
                    print(Date().timeIntervalSince(start))
                }
            }
        }

        for (i, tcs) in tcss.enumerated() {
            Task {
                try await Task.sleep(
                    for: .microseconds(i % 2 == 0 ? 5 : 15))
                _ = await tcs.trySetResult(.success(()))
            }
        }

        await fulfillment(of: [expectation], timeout: 1)
    }
}

actor Counter {
    var value: Int
    init(value: Int) {
        self.value = value
    }
    func increase(delta: Int) -> Int {
        value += delta
        return value
    }
}
