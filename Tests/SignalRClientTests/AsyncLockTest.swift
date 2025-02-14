import XCTest
@testable import SignalRClient

class AsyncLockTests: XCTestCase {
    func testLock_WhenNotLocked_Succeeds() async {
        let asyncLock = AsyncLock()
        await asyncLock.wait()
        asyncLock.release()
    }

    func testLock_SecondLock_Waits() async throws {
        let expectation = XCTestExpectation(description: "wait() should be called")
        let asyncLock = AsyncLock()
        await asyncLock.wait()
        let t = Task {
            await asyncLock.wait()
            defer {
                asyncLock.release()
            }
            expectation.fulfill()
        }

        asyncLock.release()
        await fulfillment(of: [expectation], timeout: 2.0)
        t.cancel()
    }
}