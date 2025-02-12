import Foundation

class AsyncLock {
    let lock = DispatchSemaphore(value: 1)
    private var isLocked = false
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        lock.wait()

        if !isLocked {
            defer {
                lock.signal()
            }

            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            defer {lock.signal()}
            waitQueue.append(continuation)
        }
    }

    func release() {
        lock.wait()
        defer {
            lock.signal()
        }

        if let continuation = waitQueue.first {
            waitQueue.removeFirst()
            continuation.resume() 
        } else {
            isLocked = false
        }
    }
}
