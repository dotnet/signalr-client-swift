public protocol StreamResult<Element> {
    associatedtype Element
    var stream: AsyncStream<Element> { get }
    func cancel()
}