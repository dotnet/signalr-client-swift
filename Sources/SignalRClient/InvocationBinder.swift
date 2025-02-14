import Foundation

protocol InvocationBinder: Sendable{
    func getReturnType(invocationId: String) -> Any.Type?
    func getParameterTypes(methodName: String) -> [Any.Type]
    func getStreamItemType(streamId: String) -> Any.Type?
}
