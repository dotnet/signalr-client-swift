public protocol StreamResult<Element> {
    associatedtype Element
    var stream: AsyncThrowingStream<Element, Error> { get }
    func cancel() async
}