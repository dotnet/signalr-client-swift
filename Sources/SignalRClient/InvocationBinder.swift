// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

protocol InvocationBinder: Sendable{
    func getReturnType(invocationId: String) -> Any.Type?
    func getParameterTypes(methodName: String) -> [Any.Type]
    func getStreamItemType(streamId: String) -> Any.Type?
}
