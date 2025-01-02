public protocol StreamResult<Element> {
    associatedtype Element
    func subscribe(subscriber: any StreamSubscriber<Element>) async
}


/// A protocol that defines the methods and properties required for a stream subscriber.
/// A stream subscriber is an entity that can receive values, handle errors, and be notified of stream completion.
public protocol StreamSubscriber<Element> {
    associatedtype Element

    /// A Boolean value indicating whether the stream is closed.
    var closed: Bool { get }
    
    /// Called when a new value is received from the stream.
    /// - Parameter value: The value received from the stream.
    func next(value: Element) async
    
    /// Called when an error occurs in the stream.
    /// - Parameter error: The error that occurred.
    func error(error: Error) async
    
    /// Called when the stream is completed.
    func complete() async
}