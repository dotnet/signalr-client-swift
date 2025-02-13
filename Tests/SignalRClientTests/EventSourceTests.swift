// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation
import XCTest

@testable import SignalRClient

class EventSourceTests: XCTestCase {
    func testEventParser() async throws {
        let parser = EventParser()

        var content = "data:hello\n\n".data(using: .utf8)!
        var events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "hello")

        content = "data: hello\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "hello")

        content = "data: hello\r\n\r\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "hello")

        content = "data: hello\r\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "hello")

        content = "data:  hello\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], " hello")

        content = "data:\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "")

        content = "data\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "")

        content = "data\ndata\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "\n")

        content = "data:\ndata\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "\n")

        content = "dat".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 0)

        content = "a:e\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "e")

        content = ":\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 0)

        content = "retry:abc\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 0)

        content = "dataa:abc\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 0)

        content = "Data:abc\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 0)

        content = "data:abc \ndata\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "abc \n")

        content = "data:abc \ndata:efg\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0], "abc \nefg")

        content = "data:abc \ndata:efg\n\nretry\ndata:h\n\n".data(using: .utf8)!
        events = parser.Parse(data: content)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], "abc \nefg")
        XCTAssertEqual(events[1], "h")
    }
}
