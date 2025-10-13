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
    private var nextReceivingIdx: Int64 = 1
    private var lastReceivedSequenceId: Int64 = 0
    private var dequeueContinuations: [CheckedContinuation<Bool, Never>] = []
    private var closed: Bool = false
    private var reconnectInprogress: Bool = false;
    private var waitForSequenceMessage: Bool = false;

    private var ackTimerHandle: DispatchWorkItem?

    private var hubProtocol: HubProtocol;
    private var connection: ConnectionProtocol;

    init(bufferSize: Int, hubProtocol: HubProtocol, connection: ConnectionProtocol) {
        self.maxBufferSize = bufferSize
        self.hubProtocol = hubProtocol
        self.connection = connection
    }

    public func send(message: HubMessage) async throws -> Void {
        let serializedMessage = try self.hubProtocol.writeMessage(message: message);

        var backpressurePromise: Task<Void, Never>? = nil

        // Only count invocation messages. Acks, pings, etc. don't need to be resent on reconnect
        if (self.isInvocationMessage(message: message)) {
            backpressurePromise = Task {
                try? await self.enqueue(content: serializedMessage)
            }
        }

        do {
            // If this is set it means we are reconnecting or resending
            // We don't want to send on a disconnected connection
            // And we don't want to send if resend is running since that would mean sending
            // this message twice
            if (!self.reconnectInprogress) {
                try await self.connection.send(serializedMessage);
            }
        } catch {
            self.disconnected();
        }
        
        if let backpressureTask = backpressurePromise {
            await backpressureTask.value
        }
    }

    public func resend() async throws -> Void {
        // Reset nextSendIdx to ensure resending from the beginning of the message queue
        self.nextSendIdx = 0;
        
        let sequenceId = Int64(self.messages.count > 0 ? self.messages[0].id : self.totalMessageCount + 1);
        let serializedMessage = try self.hubProtocol.writeMessage(message: SequenceMessage(sequenceId: sequenceId));
        try await self.connection.send(serializedMessage);
        
        // Get a local variable to the messages, just in case messages are acked while resending
        // Which would slice the messages array (which creates a new copy)
        while let element = try self.TryDequeue() {
            try await self.connection.send(element);
        }

        self.reconnectInprogress = false;
    }

    public func disconnected() -> Void {
        self.reconnectInprogress = true;
        self.waitForSequenceMessage = true;
    }

    private func ackTimer() {
        guard ackTimerHandle == nil else {
            return
        }
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            Task {
                await self.performScheduledAck()
            }
        }
        
        ackTimerHandle = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func performScheduledAck() async {
        defer {
            ackTimerHandle = nil
        }
        
        do {
            if !reconnectInprogress {
                let ackMessage = AckMessage(
                    sequenceId: lastReceivedSequenceId
                )
                
                let serializedMessage = try hubProtocol.writeMessage(message: ackMessage)
                try await connection.send(serializedMessage)
            }
        } catch {
            // Ignore exception, no need to send ACK when reconnecting
        }
    }

    public func shouldProcessMessage(_ message: HubMessage) throws -> Bool {
        if (self.waitForSequenceMessage) {
            if (message.type != .sequence) {
                return false;
            } else {
                self.waitForSequenceMessage = false;
                return true;
            }
        }

        if !self.isInvocationMessage(message: message) {
            return true
        }

        let currentId = self.nextReceivingIdx;
        self.nextReceivingIdx += 1;
        if currentId <= self.lastReceivedSequenceId{
            if currentId == self.lastReceivedSequenceId{
                // Should only hit this if we just reconnected and the server is sending
                // Messages it has buffered, which would mean it hasn't seen an Ack for these messages
                self.ackTimer();
            }
            // Ignore, this is a duplicate message
            return false;
        }
        self.lastReceivedSequenceId = currentId;

        // Only start the timer for sending an Ack message when we have a message to ack. This also conveniently solves
        // timer throttling by not having a recursive timer, and by starting the timer via a network call (recv)
        self.ackTimer();
        return true;     
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

    public func ack(sequenceId: Int64) -> Bool {
        // It might be wrong ack
        // Question: sequenceId > lastSendSequenceId shall be acceptable for the sequenceIds may not be continous?
        // See https://github.com/dotnet/aspnetcore/blob/v9.0.9/src/SignalR/clients/ts/signalr/tests/HubConnection.test.ts#L2007
        if (sequenceId <= 0) {
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

        if (ackedCount > 0) {
            messages = Array(messages.dropFirst(ackedCount))
            // sending idx will change because we changes the array
            // Why max: example: self.messages.length is 3, sequenceId is 2, nextSendIdx is 0, ackedCount is 2
            nextSendIdx = max(0, nextSendIdx - ackedCount)
            return true
        }
        return false
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

        // Unblock backpressure if any
        for element in messages {
            if let continuation = element.continuation {
                continuation.resume()
            }
        }

        while !dequeueContinuations.isEmpty {
            let continuation = dequeueContinuations.removeFirst()
            continuation.resume(returning: false)
        }
    }

    public func resetSequenceMessage(message: SequenceMessage) async {
        if message.sequenceId > self.nextReceivingIdx {
            // do not await stop
            Task {
                await self.connection.stop(error: SignalRError.invalidOperation("Received sequence message with sequenceId \(message.sequenceId) greater than nextReceivingIdx \(self.nextReceivingIdx)"))
            }
            return 
        }
        self.nextReceivingIdx = message.sequenceId;
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