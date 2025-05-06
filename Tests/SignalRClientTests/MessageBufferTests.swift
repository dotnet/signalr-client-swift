import XCTest

@testable import SignalRClient

class MessageBufferTest: XCTestCase {
    func testSendWithinBufferSize() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        let expectation = XCTestExpectation(description: "Should enqueue")
        Task {
            try await buffer.enqueue(content: .string("data"))
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testSendTriggersBackpressure() async throws {
        let buffer = MessageBuffer(bufferSize: 5)
        let expectation1 = XCTestExpectation(description: "Should not enqueue")
        expectation1.isInverted = true
        let expectation2 = XCTestExpectation(description: "Should enqueue")
        Task {
            try await buffer.enqueue(content: .string("123456"))
            expectation1.fulfill()
            expectation2.fulfill()
        }
        
        await fulfillment(of: [expectation1], timeout: 0.5)
        let content = try await buffer.TryDequeue() // Only after dequeue, the ack takes effect
        XCTAssertEqual("123456", content?.convertToString())
        let rst = try await buffer.ack(sequenceId: 1)
        XCTAssertEqual(true, rst)
        await fulfillment(of: [expectation2], timeout: 1)
    }

    func testBackPressureAndRelease() async throws {
        let buffer = MessageBuffer(bufferSize: 10)
        try await buffer.enqueue(content: .string("1234567890"))
        async let eq1 = buffer.enqueue(content: .string("1"))
        async let eq2 = buffer.enqueue(content: .string("2"))

        try await Task.sleep(for: .microseconds(10))
        try await buffer.TryDequeue() // 1234567890
        try await buffer.TryDequeue() // 1
        try await buffer.TryDequeue() // 2
        
        // ack 1 and all should be below 
        try await buffer.ack(sequenceId: 1)

        try await eq1
        try await eq2
    }

    func testBackPressureAndRelease2() async throws {
        let buffer = MessageBuffer(bufferSize: 10)
        let expect1 = XCTestExpectation(description: "Should not release 1")
        expect1.isInverted = true
        let expect2 = XCTestExpectation(description: "Should not release 2")
        expect2.isInverted = true
        let expect3 = XCTestExpectation(description: "Should not release 3")
        expect3.isInverted = true

        try await buffer.enqueue(content: .string("1234567890")) //10
        try await Task.sleep(for: .microseconds(10)) 
        let t1 = Task { 
            try await buffer.enqueue(content: .string("1"))
            expect1.fulfill()
        }// 11
        try await Task.sleep(for: .microseconds(10))
        let t2 = Task { 
            try await buffer.enqueue(content: .string("2")) 
            expect2.fulfill()
        }// 12
        try await Task.sleep(for: .microseconds(10))
        let t3 = Task {
            try await buffer.enqueue(content: .string("123456789")) 
            expect3.fulfill()
        }// 21
        try await Task.sleep(for: .microseconds(10))

        try await buffer.TryDequeue() // 1234567890
        try await buffer.TryDequeue() // 1
        try await buffer.TryDequeue() // 2
        try await buffer.TryDequeue() // 1234567890
        
        // ack 1 and all should be below 
        try await buffer.ack(sequenceId: 1) // remain 11, nothing will release

        await fulfillment(of: [expect1, expect2, expect3], timeout: 0.5)
        try await buffer.ack(sequenceId: 2) // remain 10, all released
        await t1.result
        await t2.result
        await t3.result
    }

    func testAckInvalidSequenceIdIgnored() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        let rst = try await buffer.ack(sequenceId: 1) // without any send
        XCTAssertEqual(false, rst)
        
        // Enqueue but not send
        try await buffer.enqueue(content: .string("abc"))
        let rst2 = try await buffer.ack(sequenceId: 1)
        XCTAssertEqual(false, rst2)
    }

    func testWaitToDequeueReturnsImmediatelyIfAvailable() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        _ = try await buffer.enqueue(content: .string("msg"))
        let result = try await buffer.WaitToDequeue()
        XCTAssertTrue(result)
        let content = try await buffer.TryDequeue()
        XCTAssertEqual("msg", content?.convertToString())
    }

    func testWaitToDequeueFirst() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        async let dqueue: Bool = try await buffer.WaitToDequeue()
        try await Task.sleep(for: .milliseconds(10))

        try await buffer.enqueue(content: .string("test"))
        try await buffer.enqueue(content: .string("test2"))

        let rst = try await dqueue
        XCTAssertTrue(rst)
        let content = try await buffer.TryDequeue()
        XCTAssertEqual("test", content?.convertToString())
    }

    func testMultipleDequeueWait() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        async let dqueue1: Bool = try await buffer.WaitToDequeue()
        async let dqueue2: Bool = try await buffer.WaitToDequeue()
        try await Task.sleep(for: .milliseconds(10))

        try await buffer.enqueue(content: .string("test"))

        let rst = try await dqueue1
        XCTAssertTrue(rst)
        let rst2 = try await dqueue2
        XCTAssertTrue(rst2)
        let content = try await buffer.TryDequeue()
        XCTAssertEqual("test", content?.convertToString())
    }

    func testTryDequeueReturnsNilIfEmpty() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        let result = try await buffer.TryDequeue()
        XCTAssertNil(result)
    }

    func testResetDequeueResetsCorrectly() async throws {
        let buffer = MessageBuffer(bufferSize: 100)
        try await buffer.enqueue(content: .string("test1"))
        try await buffer.enqueue(content: .string("test2"))
        let t1 = try await buffer.TryDequeue()
        XCTAssertEqual("test1", t1?.convertToString())
        let t2 = try await buffer.TryDequeue()
        XCTAssertEqual("test2", t2?.convertToString())

        // wait here
        async let dq = try await buffer.WaitToDequeue()
        try await Task.sleep(for: .milliseconds(10))
        Task {
            try await buffer.ResetDequeue()
        }

        try await dq
        let t3 = try await buffer.TryDequeue()
        XCTAssertEqual("test1", t3?.convertToString())
        let t4 = try await buffer.TryDequeue()
        XCTAssertEqual("test2", t4?.convertToString())
    }

    func testContinuousBackPressure() async throws {
        let buffer = MessageBuffer(bufferSize: 5)
        var tasks: [Task<Void, any Error>] = []
        for i in 0..<100 {
            let task = Task {
                try await buffer.enqueue(content: .string("123456"))
            }
            tasks.append(task)
        }

        Task {
            while (try await buffer.WaitToDequeue()) {
                try await buffer.TryDequeue()
            }
        }

        for i in 0..<100 {
            await tasks[i]
        }

        await buffer.close()
    }
}