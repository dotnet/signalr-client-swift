import Foundation

class InvocationHandler {
    private var methods: [String: InvocationEntity] = [:]

    func on(methodName: String, types: [Any.Type], callback: @escaping ([Any]) async throws -> Void) {
        methods[methodName] = InvocationEntity(types: types, callback: callback)
    }

    func trigger(methodName: String, arguments: [Any]) async throws {
        guard let invocationEntity = methods[methodName] else {
            return
        }

        if invocationEntity.types.count != arguments.count {
            throw SignalRError.invalidOperation("Stringly typed hub methods must have the same number of arguments as the method signature.")
        }

        // for (index, argument) in arguments.enumerated() {
        //     if !invocationEntity.types[index].isInstance(of: argument) {
        //         throw SignalRError.invalidOperation("Argument at index \(index) is not of the expected type.")
        //     }
        // }

        try await invocationEntity.callback(arguments)
    }

    private class InvocationEntity {
        let types: [Any.Type]
        let callback: ([Any]) async throws -> Void

        init(types: [Any.Type], callback: @escaping ([Any]) async throws -> Void) {
            self.types = types
            self.callback = callback
        }
    }
}

struct InvocationBinder {
    private let binderTypes: [Any.Type]

    init(binderTypes: [Any.Type]) {
        self.binderTypes = binderTypes
    }

    func GetBinderTypes() -> [Any.Type] {
        return binderTypes
    }
}