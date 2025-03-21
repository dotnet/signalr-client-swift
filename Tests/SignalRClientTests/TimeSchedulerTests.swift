// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import XCTest
@testable import SignalRClient

class TimeSchedulerrTests: XCTestCase {
    var scheduler: TimeScheduler!
    var sendActionCalled: Bool!
    
    override func setUp() {
        super.setUp()
        scheduler = TimeScheduler(initialInterval: 0.1)
        sendActionCalled = false
    }
    
    override func tearDown() async throws {
        await scheduler.stop()
        scheduler = nil
        sendActionCalled = nil
        try await super.tearDown()
    }
    
    func testStart() async {
        let expectations = [
            self.expectation(description: "sendAction called"),
            self.expectation(description: "sendAction called"),
            self.expectation(description: "sendAction called")
        ]
        
        var counter = 0
        await scheduler.start {
            if counter <= 2 {
                expectations[counter].fulfill()
            }
            counter += 1
        }
        
        await fulfillment(of: [expectations[0], expectations[1], expectations[2]], timeout: 1)
    }
    
    func testStop() async {
        let stopExpectation = self.expectation(description: "sendAction not called")
        stopExpectation.isInverted = true
        
        await scheduler.start {
            stopExpectation.fulfill()
        }
        
        await scheduler.stop()

        await fulfillment(of: [stopExpectation], timeout: 0.5)
    }
    
    func testUpdateInterval() async {
        let invertedExpectation = self.expectation(description: "Should not called")
        invertedExpectation.isInverted = true
        let expectation = self.expectation(description: "sendAction called")
        await scheduler.updateInterval(to: 5)

        await scheduler.start {
            invertedExpectation.fulfill()
            expectation.fulfill()
        }

        await fulfillment(of: [invertedExpectation], timeout: 0.5)
        await scheduler.updateInterval(to: 0.1)

        await fulfillment(of: [expectation], timeout: 1)
    }
}