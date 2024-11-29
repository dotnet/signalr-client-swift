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
        XCTAssertLessThan(abs(elapsed - 1), 1)
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
        XCTAssertLessThan(elapsed, 1)
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
                error as? SignalRError, SignalRError.noHandshakeMessageReceived)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(abs(elapsed - 1), 1)
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
        XCTAssertLessThan(abs(elapsed - 1), 1)
        
        let start2 = Date()
        let value2 = try await tcs.task()
        let elapsed2 = Date().timeIntervalSince(start2)
        XCTAssertTrue(value2)
        XCTAssertLessThan(elapsed2, 1)
        
        try await t.value
    }
}
