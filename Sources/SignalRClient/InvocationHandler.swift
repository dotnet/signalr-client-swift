import Foundation

protocol InvocationBinder {
    func GetReturnType(invocationId: String) -> Any.Type?
    func GetParameterTypes(methodName: String) -> [Any.Type]
    func GetStreamItemType(streamId: String) -> Any.Type?
}
