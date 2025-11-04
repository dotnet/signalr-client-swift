// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

public protocol StreamResult<Element>: Sendable {
    associatedtype Element
    var stream: AsyncThrowingStream<Element, Error> { get }
    func cancel() async
}