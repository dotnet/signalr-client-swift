// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

actor MessageBuffer {
    private var maxBufferSize: Int
    private var messages: [BufferedItem] = []
    private var bufferedByteCount: Int = 0
    private var totalMessageCount: Int = 0
    private var lastSendSequenceId: Int = 0
    private var nextSendIdx = 0
    private var dequeueContinuations: [CheckedContinuation<Bool, Never>] = []
    private var closed: Bool = false

    init(bufferSize: Int) {
        self.maxBufferSize = bufferSize
    }

    public func enqueue(content: StringOrData) async throws -> Void {
        if closed {
            throw SignalRError.invalidOperation("Message buffer has closed")
        }

        var size: Int
        switch content {
        case .string(let str):
            size = str.lengthOfBytes(using: .utf8)
        case .data(let data):
            size = data.count
        }

        bufferedByteCount = bufferedByteCount + size
        totalMessageCount = totalMessageCount + 1

        return await withCheckedContinuation{ continuation in
            if (bufferedByteCount > maxBufferSize) {
                // If buffer is full, we're tring to backpressure the sending
                // id start from 1
                messages.append(BufferedItem(content: content, size: size, id: totalMessageCount, continuation: continuation))
            } else {            
                messages.append(BufferedItem(content: content, size: size, id: totalMessageCount, continuation: nil))
                continuation.resume()
            }

            while !dequeueContinuations.isEmpty {
                let continuation = dequeueContinuations.removeFirst()
                continuation.resume(returning: true)
            }
        }
    }

    public func ack(sequenceId: Int) throws -> Bool {
        // It might be wrong ack or the ack of previous connection
        if (sequenceId <= 0 || sequenceId > lastSendSequenceId) {
            return false
        }

        var ackedCount: Int = 0
        for item in messages {
            if (item.id <= sequenceId) {
                ackedCount = ackedCount + 1
                bufferedByteCount = bufferedByteCount - item.size
                if let ctu = item.continuation {
                    ctu.resume()
                }
            } else if (bufferedByteCount <= maxBufferSize) {
                if let ctu = item.continuation {
                    ctu.resume()
                }
            } else {
                break
            }
        }

        messages = Array(messages.dropFirst(ackedCount))
        // sending idx will change because we changes the array
        nextSendIdx = nextSendIdx - ackedCount
        return true
    }

    public func WaitToDequeue() async throws -> Bool {
        if (nextSendIdx < messages.count) {
            return true
        }

        return await withCheckedContinuation { continuation in
            dequeueContinuations.append(continuation)
        }
    }

    public func TryDequeue() throws -> StringOrData? {
        if (nextSendIdx < messages.count) {
            let item =  messages[nextSendIdx]
            nextSendIdx = nextSendIdx + 1
            lastSendSequenceId = item.id
            return item.content
        }
        return nil
    }

    public func ResetDequeue() async throws -> Void {
        nextSendIdx = 0
        lastSendSequenceId = messages.count > 0 ? messages[0].id : 0
        while !dequeueContinuations.isEmpty {
            let continuation = dequeueContinuations.removeFirst()
            continuation.resume(returning: true)
        }
    }

    public func close() {
        closed = true
        while !dequeueContinuations.isEmpty {
            let continuation = dequeueContinuations.removeFirst()
            continuation.resume(returning: false)
        }
    }

    private func isInvocationMessage(message: HubMessage) -> Bool {
        switch (message.type) {
            case .invocation, .streamItem, .completion, .streamInvocation, .cancelInvocation:
            return true
            case .close, .sequence, .ping, .ack:
            return false
        }
    }
}

private class BufferedItem {
    let content: StringOrData
    let size: Int
    let id: Int
    let continuation: CheckedContinuation<Void, Never>?

    init(content: StringOrData,
         size: Int,
         id: Int,
         continuation: CheckedContinuation<Void, Never>?) {
        self.content = content
        self.size = size
        self.id = id
        self.continuation = continuation
    }
}