// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

actor MessageBuffer {
    private var maxBufferSize: Int
    private var messages: [BufferedItem] = []
    private var bufferedByteCount: Int = 0
    private var totalMessageCount: Int = 0
    private var lastSendSequenceId: Int = 0
    private var lastSendIdx = 0
    private var dequeueContinuation: CheckedContinuation<Bool, Never>?
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

            if let continuation = dequeueContinuation {
                continuation.resume(returning: true)
            }
        }
    }

    public func ack(sequenceId: Int) throws -> Bool {
        // It might be wrong ack or the ack of previous connection
        if (sequenceId <= 0 || sequenceId > lastSendSequenceId) {
            return false
        }

        let pfx = messages.prefix {$0.id <= sequenceId}
        let itemsToProcess = Array(pfx)
        // make sure remove before any async operation for concurrency issue
        messages = Array(messages.dropFirst(pfx.count))
        // sending idx will change because we changes the array
        lastSendIdx = lastSendIdx - pfx.count

        guard lastSendIdx >= 0 else {
            throw SignalRError.invalidOperation("Index of the ack < 0, fatal error")
        }

        for item in itemsToProcess {
            bufferedByteCount = bufferedByteCount - item.size
            if let ctu = item.continuation {
                ctu.resume()
            }
        }
        return true
    }

    public func WaitToDequeue() async throws -> Bool {
        let lastEnqueuedIdx = messages.count - 1
        if (lastSendIdx <= lastEnqueuedIdx) {
            return true
        }
        return await withCheckedContinuation { continuation in
            dequeueContinuation = continuation
        }
    }

    public func TryDequeue() throws -> StringOrData? {
        let lastEnqueuedIdx = messages.count - 1
        if (lastSendIdx <= lastEnqueuedIdx) {
            let item =  messages[lastSendIdx]
            lastSendIdx = lastSendIdx + 1
            lastSendSequenceId = item.id
            return item.content
        }
        return nil
    }

    public func ResetDequeue() async throws -> Void {
        lastSendIdx = 0
        lastSendSequenceId = messages.count > 0 ? messages[0].id : 0
        if let continuation = dequeueContinuation {
            continuation.resume(returning: true)
        }
    }

    public func close() {
        closed = true
        if let continuation = dequeueContinuation {
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