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
    
    override func tearDown() {
        scheduler.stop()
        scheduler = nil
        sendActionCalled = nil
        super.tearDown()
    }
    
    func testStart() async {
        let expectations = [
            self.expectation(description: "sendAction called"),
            self.expectation(description: "sendAction called"),
            self.expectation(description: "sendAction called")
        ]
        
        var counter = 0
        scheduler.start {
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
        
        scheduler.start {
            stopExpectation.fulfill()
        }
        
        scheduler.stop()

        await fulfillment(of: [stopExpectation], timeout: 0.5)
    }
    
    func testUpdateInterval() async {
        let invertedExpectation = self.expectation(description: "Should not called")
        invertedExpectation.isInverted = true
        let expectation = self.expectation(description: "sendAction called")
        scheduler.updateInterval(to: 5)

        scheduler.start {
            invertedExpectation.fulfill()
            expectation.fulfill()
        }

        await fulfillment(of: [invertedExpectation], timeout: 0.5)
        scheduler.updateInterval(to: 0.1)

        await fulfillment(of: [expectation], timeout: 1)
    }
}