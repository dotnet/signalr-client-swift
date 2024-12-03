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
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid input for JSON hub protocol. Expected a string."])
        }

        if inputString.isEmpty {
            return []
        }

        let messages = try TextMessageFormat.parse(inputString)
        var hubMessages = [HubMessage]()

        for message in messages {
            guard let data = message.data(using: .utf8) else {
                throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid message encoding."])
            }
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let type = jsonObject["type"] as? Int {
                    switch type {
                        case 1:
                            let result = try DecodeInvocationMessage(jsonObject, binder: binder)
                            hubMessages.append(result)
                        case 2:
                            let result = try JSONDecoder().decode(StreamItemMessage.self, from: data)
                            hubMessages.append(result)
                        case 3:
                            let result = try JSONDecoder().decode(CompletionMessage.self, from: data)
                            hubMessages.append(result)
                        case 4:
                            let result = try JSONDecoder().decode(StreamInvocationMessage.self, from: data)
                            hubMessages.append(result)
                        case 5:
                            let result = try JSONDecoder().decode(CancelInvocationMessage.self, from: data)
                            hubMessages.append(result)
                        case 6:
                            let result = try JSONDecoder().decode(PingMessage.self, from: data)
                            hubMessages.append(result)
                        case 7:
                            let result = try JSONDecoder().decode(CloseMessage.self, from: data)
                            hubMessages.append(result)
                        case 8:
                            let result = try JSONDecoder().decode(AckMessage.self, from: data)
                            hubMessages.append(result)
                        case 9:
                            let result = try JSONDecoder().decode(SequenceMessage.self, from: data)
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
            throw NSError(domain: "JsonHubProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON data to string."])
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
        let typedArguments = try DecodeArguments(jsonObject, binder: binder)

        return InvocationMessage(target: target, arguments: typedArguments, streamIds: streamIds, headers: headers, invocationId: invocationId)
    }

    private func DecodeArguments(_ jsonObject: [String: Any], binder: InvocationBinder) throws -> [AnyCodable] {
        let arguments = jsonObject["arguments"] as? [Any] ?? []
        let types = binder.GetBinderTypes()
        guard arguments.count == types.count else {
            throw SignalRError.invalidData("Invocation provides \(arguments.count) argument(s) but target expects \(types.count).")
        }

        return try zip(arguments, types).map { (arg, type) in
            return try convertToType(arg, as: type)
        }
    }

    private func convertToType(_ anyObject: Any, as targetType: Any.Type) throws -> AnyCodable {
        guard let decodableType = targetType as? Decodable.Type else {
            throw SignalRError.invalidData("Provided type does not conform to Decodable.")
        }
        
        // Step 2: Convert dictionary to JSON data
        guard let jsonData = try? JSONSerialization.data(withJSONObject: anyObject) else {
            throw SignalRError.invalidData("Failed to serialize dictionary to JSON data.")
        }
        
        // Step 3: Decode JSON data into the target type
        let decoder = JSONDecoder()
        let decodedObject = try decoder.decode(decodableType, from: jsonData)
        return AnyCodable(decodedObject)
    }
}