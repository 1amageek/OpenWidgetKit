@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation {
    package let key: String
    package let arguments: [String]

    public init(_ value: String) {
        key = value
        arguments = []
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        package private(set) var key: String
        package private(set) var arguments: [String]

        public init(literalCapacity: Int, interpolationCount: Int) {
            key = ""
            key.reserveCapacity(literalCapacity + interpolationCount * 2)
            arguments = []
            arguments.reserveCapacity(interpolationCount)
        }

        public mutating func appendLiteral(_ literal: String) {
            key.append(literal)
        }

        public mutating func appendInterpolation(_ string: String) {
            appendArgument(string)
        }

        public mutating func appendInterpolation(_ substring: Substring) {
            appendArgument(String(substring))
        }

        public mutating func appendInterpolation<T>(_ value: T)
        where T: CustomStringConvertible {
            appendArgument(value.description)
        }

        private mutating func appendArgument(_ value: String) {
            key.append("%@")
            arguments.append(value)
        }
    }
}
