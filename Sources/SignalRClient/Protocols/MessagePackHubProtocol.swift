// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

import Foundation

final class MessagePackHubProtocol: HubProtocol {
    let name = "messagepack"
    let version = 0
    let transferFormat: TransferFormat = .binary

    func parseMessages(input: StringOrData, binder: any InvocationBinder) throws
    -> [any HubMessage] {
        var data: Data
        switch input {
        case .string(_):
            throw SignalRError.invalidData(
                "Invalid input for MessagePack hub protocol. Expected Data.")
        case .data(let d):
            data = d
            break
        }
        var hubMessages: [HubMessage] = []
        let messages = try BinaryMessageFormat.parse(data)
        for message in messages {
            guard
                let hubMessage = try parseMessage(
                    message: message, binder: binder
                )
            else {
                continue
            }
            hubMessages.append(hubMessage)
        }

        return hubMessages
    }

    func writeMessage(message: any HubMessage) throws -> StringOrData {
        var arr: [Any?]
        switch message {
        case let message as InvocationMessage:
            arr = [
                message.type, message.headers ?? [:], message.invocationId,
                message.target, message.arguments,
            ]
            if message.streamIds != nil {
                arr.append(message.streamIds)
            }
        case let message as StreamInvocationMessage:
            arr = [
                message.type, message.headers ?? [:], message.invocationId,
                message.target, message.arguments,
            ]
            if message.streamIds != nil {
                arr.append(message.streamIds)
            }
        case let message as PingMessage:
            arr = [message.type]
        case let message as CloseMessage:
            arr =
                [message.type, message.error]
        case let message as CancelInvocationMessage:
            arr = [
                message.type, message.headers ?? [:], message.invocationId,
            ]
        case let message as StreamItemMessage:
            arr = [
                message.type, message.headers ?? [:], message.invocationId,
                message.item,
            ]
        case let message as SequenceMessage:
            arr = [message.type, message.sequenceId]
        case let message as AckMessage:
            arr = [message.type, message.sequenceId]
        case let message as CompletionMessage:
            if message.error != nil {
                arr = [
                    message.type, message.headers ?? [:], message.invocationId,
                    1,
                    message.error,
                ]
                // Set ResultKind = 2 will trigger a server side issue
//            } else if message.result.value == nil {
//                arr = [
//                    message.type, message.headers ?? [:], message.invocationId,
//                    2
//                ]
            } else {
                arr = [
                    message.type, message.headers ?? [:], message.invocationId,
                    3,
                    message.result.value,
                ]
            }
        default:
            throw SignalRError.unexpectedMessageType("\(type(of: message))")
        }
        let messageData = try MsgpackEncoder().encode(
            AnyEncodableArray(arr))
        return try .data(BinaryMessageFormat.write(messageData))
    }

    func parseMessage(message: Data, binder: any InvocationBinder)
    throws -> HubMessage? {
        let (msgpackElement, _) = try MsgpackElement.parse(data: message)
        let decoder = MsgpackDecoder()
        try decoder.loadMsgpackElement(from: msgpackElement)
        var container = try decoder.unkeyedContainer()
        guard
            let messageType = MessageType(
                rawValue: try container.decode(Int.self))
        else {
            // TODO: log new type
            return nil
        }
        switch messageType {
        case MessageType.invocation:
            guard container.count! >= 4 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Invocation message."
                )
            }
            let headers = try container.decode([String: String]?.self)
            let invocationId = try container.decode(String?.self)
            let target = try container.decode(String.self)
            let argumentTypes = binder.getParameterTypes(methodName: target)
            var subContainer = try container.nestedUnkeyedContainer()
            var arguments: [Any] = []
            for t in argumentTypes {
                guard let argumentType = t as? Decodable.Type else {
                    throw SignalRError.invalidData(
                        "Provided type \(t) does not conform to Decodable.")
                }
                let argument = try subContainer.decode(argumentType)
                arguments.append(argument)
            }
            return
                InvocationMessage(
                    target: target, arguments: AnyEncodableArray(arguments),
                    streamIds: [],
                    headers: headers, invocationId: invocationId
                )

        case MessageType.streamItem:
            guard container.count! >= 4 else {
                throw SignalRError.invalidData(
                    "Invalid payload for StreamItem message.")
            }
            let headers = try container.decode([String: String]?.self)
            let invocationId = try container.decode(String.self)
            guard
                let streamItemType = binder.getStreamItemType(
                    streamId: invocationId) as? Decodable.Type
            else {
                throw SignalRError.invalidData("No item type found in binder.")
            }
            let item = try container.decode(streamItemType)
            return StreamItemMessage(
                invocationId: invocationId, item: AnyEncodable(item),
                headers: headers
            )

        case MessageType.completion:
            guard container.count! >= 4 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Completion message.")
            }
            let headers = try container.decode([String: String]?.self)
            let invocationId = try container.decode(String.self)
            let resultKind = try container.decode(Int8.self)
            guard resultKind == 2 || container.count! >= 5 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Completion message.")
            }
            var error: String? = nil
            var result: Any? = nil
            switch resultKind {
            case 1:
                error = try container.decode(String?.self)
            case 2:
                break
            case 3:
                guard
                    let returnType = binder.getReturnType(
                        invocationId: invocationId)
                else {
                    break
                }
                guard
                    let returnType = returnType as? Decodable.Type
                else {
                    throw SignalRError.invalidData(
                        "Provided type \(returnType) does not conform to Decodable.")
                }
                result = try container.decode(returnType)
            default:
                // new result type. Ignore
                break
            }
            return CompletionMessage(
                invocationId: invocationId, error: error,
                result: AnyEncodable(result), headers: headers
            )

        case MessageType.cancelInvocation:
            guard container.count! >= 3 else {
                throw SignalRError.invalidData(
                    "Invalid payload for CancelInvocation message.")
            }
            let headers = try container.decode([String: String]?.self)
            let invocationId = try container.decode(String?.self)
            return CancelInvocationMessage(
                invocationId: invocationId,
                headers: headers
            )

        case MessageType.ping:
            return PingMessage()

        case MessageType.close:
            guard container.count! >= 2 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Close message.")
            }
            let err = try container.decode(String?.self)
            let allowReconnect =
                container.isAtEnd ? nil : try container.decode(Bool?.self)
            return CloseMessage(error: err, allowReconnect: allowReconnect)

        case MessageType.ack:
            guard container.count! >= 2 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Ack message.")
            }
            let sequenceId = try container.decode(Int64.self)
            return AckMessage(sequenceId: sequenceId)

        case MessageType.sequence:
            guard container.count! >= 2 else {
                throw SignalRError.invalidData(
                    "Invalid payload for Sequence message.")
            }
            let sequenceId = try container.decode(Int64.self)
            return SequenceMessage(sequenceId: sequenceId)

        default:
            // StreamInvocation is not supported at client side
            return nil
        }
    }
}
