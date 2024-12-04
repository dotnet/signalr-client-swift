import Foundation

struct JsonHubProtocol: HubProtocol {
    let name = "json"
    let version = 0
    let transferFormat: TransferFormat = .text

    func parseMessages(input: StringOrData, binder: InvocationBinder) throws -> [HubMessage] {
        let inputString: String
        switch input {
            case .string(let str):
                inputString = str
            case .data:
                throw SignalRError.invalidData("Invalid input for JSON hub protocol. Expected a string.")
        }

        if inputString.isEmpty {
            return []
        }

        let messages = try TextMessageFormat.parse(inputString)
        var hubMessages = [HubMessage]()

        for message in messages {
            guard let data = message.data(using: .utf8) else {
                throw SignalRError.invalidData("Failed to convert message to data.")
            }
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = jsonObject["type"] as? Int {
                    switch type {
                        case 1:
                            let result = try DecodeInvocationMessage(jsonObject, binder: binder)
                            hubMessages.append(result)
                        case 2:
                            let result = try DecodeStreamItemMessage(jsonObject, binder: binder)
                            hubMessages.append(result)
                        case 3:
                            let result = try DecodeCompletionMessage(jsonObject, binder: binder)
                            hubMessages.append(result)
                        case 4:
                            let result = try DecodeStreamInvocationMessage(jsonObject, binder: binder)
                            hubMessages.append(result)
                        case 5:
                            let result = try DecodeCancelInvocationMessage(jsonObject)
                            hubMessages.append(result)
                        case 6:
                            let result = try DecodePingMessage(jsonObject)
                            hubMessages.append(result)
                        case 7:
                            let result = try DecodeCloseMessage(jsonObject)
                            hubMessages.append(result)
                        case 8:
                            let result = try DecodeAckMessage(jsonObject)
                            hubMessages.append(result)
                        case 9:
                            let result = try DecodeSequenceMessage(jsonObject)
                            hubMessages.append(result)
                        default:
                            // Unknown message type
                            break
                    }
                }
        }

        return hubMessages
    }

    func writeMessage(message: HubMessage) throws -> StringOrData {
        let jsonData = try JSONEncoder().encode(message)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw SignalRError.invalidData("Failed to convert JSON data to string.")
        }
        return .string(TextMessageFormat.write(jsonString))
    }

    private func DecodeInvocationMessage(_ jsonObject: [String: Any], binder: InvocationBinder) throws -> InvocationMessage {
        guard let target = jsonObject["target"] as? String else {
            throw SignalRError.invalidData("'target' not found in JSON object for InvocationMessage.")
        }

        let streamIds = jsonObject["streamIds"] as? [String]
        let headers = jsonObject["headers"] as? [String: String]
        let invocationId = jsonObject["invocationId"] as? String
        let typedArguments = try DecodeArguments(jsonObject, types: binder.GetParameterTypes(methodName: target))

        return InvocationMessage(target: target, arguments: typedArguments, streamIds: streamIds, headers: headers, invocationId: invocationId)
    }

    private func DecodeStreamInvocationMessage(_ jsonObject: [String: Any], binder: InvocationBinder) throws -> StreamInvocationMessage {
        guard let target = jsonObject["target"] as? String else {
            throw SignalRError.invalidData("'target' not found in JSON object for StreamInvocationMessage.")
        }

        let streamIds = jsonObject["streamIds"] as? [String]
        let headers = jsonObject["headers"] as? [String: String]
        let invocationId = jsonObject["invocationId"] as? String
        let typedArguments = try DecodeArguments(jsonObject, types: binder.GetParameterTypes(methodName: target))

        return StreamInvocationMessage(invocationId: invocationId, target: target, arguments: typedArguments, streamIds: streamIds, headers: headers)
    }

    private func DecodeStreamItemMessage(_ jsonObject: [String: Any], binder: InvocationBinder) throws -> StreamItemMessage {
        guard let invocationId = jsonObject["invocationId"] as? String else {
            throw SignalRError.invalidData("'invocationId' not found in JSON object for StreamItemMessage.")
        }

        let headers = jsonObject["headers"] as? [String: String]
        let typedItem = try DecodeStreamItem(jsonObject, type: binder.GetStreamItemType(streamId: invocationId))

        return StreamItemMessage(invocationId: invocationId, item: typedItem, headers: headers)
    }

    private func DecodeCompletionMessage(_ jsonObject: [String: Any], binder: InvocationBinder) throws -> CompletionMessage {
        guard let invocationId = jsonObject["invocationId"] as? String else {
            throw SignalRError.invalidData("'invocationId' not found in JSON object for CompletionMessage.")
        }

        let headers = jsonObject["headers"] as? [String: String]
        let error = jsonObject["error"] as? String
        let result = try DecodeCompletionResult(jsonObject, type: binder.GetReturnType(invocationId: invocationId))

        return CompletionMessage(invocationId: invocationId, error: error, result: result, headers: headers)
    }

    private func DecodeCancelInvocationMessage(_ jsonObject: [String: Any]) throws -> CancelInvocationMessage {
        guard let invocationId = jsonObject["invocationId"] as? String else {
            throw SignalRError.invalidData("'invocationId' not found in JSON object for CancelInvocationMessage.")
        }

        let headers = jsonObject["headers"] as? [String: String]
        return CancelInvocationMessage(invocationId: invocationId, headers: headers)
    }

    private func DecodePingMessage(_ jsonObject: [String: Any]) throws -> PingMessage {
        return PingMessage()
    }

    private func DecodeCloseMessage(_ jsonObject: [String: Any]) throws -> CloseMessage {
        let error = jsonObject["error"] as? String
        let allowReconnect = jsonObject["allowReconnect"] as? Bool

        return CloseMessage(error: error, allowReconnect: allowReconnect)
    }

    private func DecodeAckMessage(_ jsonObject: [String: Any]) throws -> AckMessage {
        guard let sequenceId = jsonObject["sequenceId"] as? Int else {
            throw SignalRError.invalidData("'sequenceId' not found in JSON object for AckMessage.")
        }

        return AckMessage(sequenceId: sequenceId)
    }

    private func DecodeSequenceMessage(_ jsonObject: [String: Any]) throws -> SequenceMessage {
        guard let sequenceId = jsonObject["sequenceId"] as? Int else {
            throw SignalRError.invalidData("'sequenceId' not found in JSON object for SequenceMessage.")
        }

        return SequenceMessage(sequenceId: sequenceId)
    }

    private func DecodeArguments(_ jsonObject: [String: Any], types: [Any.Type]) throws -> AnyEncodableArray {
        let arguments = jsonObject["arguments"] as? [Any] ?? []
        guard arguments.count == types.count else {
            throw SignalRError.invalidData("Invocation provides \(arguments.count) argument(s) but target expects \(types.count).")
        }

        return AnyEncodableArray(try zip(arguments, types).map { (arg, type) in
            return try convertToType(arg, as: type)
        })
    }

    private func DecodeStreamItem(_ jsonObject: [String: Any], type: Any.Type?) throws -> AnyEncodable {
        let item = jsonObject["item"]
        if item == nil {
            return AnyEncodable(nil)
        }

        guard type != nil else {
            throw SignalRError.invalidData("No item type found in binder.")
        }

        return try AnyEncodable(convertToType(item!, as: type!))
    }

    private func DecodeCompletionResult(_ jsonObject: [String: Any], type: Any.Type?) throws -> AnyEncodable {
        let result = jsonObject["result"]
        if result == nil || type == nil{
            return AnyEncodable(nil)
        }

        return try AnyEncodable(convertToType(result!, as: type!))
    }

    private func convertToType(_ anyObject: Any, as targetType: Any.Type) throws -> Any {
        guard let decodableType = targetType as? Decodable.Type else {
            throw SignalRError.invalidData("Provided type \(targetType) does not conform to Decodable.")
        }
        
        // Convert dictionary / array to JSON data
        if (JSONSerialization.isValidJSONObject(anyObject)) {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: anyObject) else {
                throw SignalRError.invalidData("Failed to serialize to JSON data.")
            }
        
            let decoder = JSONDecoder()
            let decodedObject = try decoder.decode(decodableType, from: jsonData)
            return decodedObject
        }

        // primay elements
        return anyObject
    }
}