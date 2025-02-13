import XCTest

@testable import SignalRClient

class UtilsTest: XCTestCase {
    func testHttpRequestExtention() {
        var options = HttpConnectionOptions()
        options.timeout = 123
        options.headers = ["a": "b", "h": "i"]
        let request = HttpRequest(method: .GET, url: "http://abc", headers: ["a": "c", "d": "e"], options: options)
        XCTAssertEqual(request.timeout, 123)
        XCTAssertEqual(request.headers["a"], "b")
        XCTAssertEqual(request.headers["d"], "e")
        XCTAssertEqual(request.headers["h"], "i")
    }

    func testStringOrDataIsEmpty() {
        XCTAssertTrue(StringOrData.string("").isEmpty())
        XCTAssertFalse(StringOrData.string("1").isEmpty())
        XCTAssertTrue(StringOrData.data(Data()).isEmpty())
        XCTAssertFalse(StringOrData.data(Data(repeating: .max, count: 1)).isEmpty())
    }

    func testUserAgent() {
        _ = Utils.getUserAgent()
    }
}
