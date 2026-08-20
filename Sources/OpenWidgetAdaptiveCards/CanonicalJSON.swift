import OpenFoundation

enum CanonicalJSON: Equatable, Sendable, Encodable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([CanonicalJSON])
    case object([String: CanonicalJSON])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    func setting(_ key: String, to value: CanonicalJSON) -> CanonicalJSON {
        guard case .object(var object) = self else { return self }
        object[key] = value
        return .object(object)
    }
}

enum CanonicalJSONEncoder {
    static func encode(_ value: CanonicalJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func string(_ value: CanonicalJSON) throws -> String {
        let data = try encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw AdaptiveCardCompilationError.serializationFailed(
                "The canonical JSON encoder did not produce UTF-8."
            )
        }
        return result
    }
}
