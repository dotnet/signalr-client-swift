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
            // print("before wait")
            await asyncLock.wait()
            defer {
                // print("release 2")
                asyncLock.release()
            }
            expectation.fulfill()
        }
        
        // print("release1")
        // try await Task.sleep(for: .seconds(1))
        asyncLock.release()
        await fulfillment(of: [expectation], timeout: 2.0)
        t.cancel()
    }

    // func testLock_concurrentLock_Waits() async {
    //     let asyncLock = AsyncLock()
    //     await asyncLock.wait()
    //     await asyncLock.wait()
    //     await asyncLock.wait()

    //     asyncLock.release()
    //     asyncLock.release()
    //     asyncLock.release()    
    // }
}