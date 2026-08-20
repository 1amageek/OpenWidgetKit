import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
@preconcurrency
@MainActor
public protocol WidgetConfiguration {
    associatedtype Body: WidgetConfiguration

    @MainActor
    @preconcurrency
    var body: Body { get }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
extension WidgetConfiguration where Body == Never {
    public var body: Never {
        preconditionFailure("A primitive WidgetConfiguration has no body.")
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 1.0, *)
@available(tvOS, unavailable)
extension Never: WidgetConfiguration {}

@MainActor
package protocol WidgetConfigurationLowering {
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition]
}

@MainActor
package func lowerWidgetConfiguration<Configuration: WidgetConfiguration>(
    _ configuration: Configuration
) throws -> [RuntimeWidgetDefinition] {
    if let lowering = configuration as? any WidgetConfigurationLowering {
        return try lowering.makeRuntimeWidgetDefinitions()
    }
    guard Configuration.Body.self != Never.self else {
        throw WidgetRuntimeError.unsupportedWidgetConfiguration(
            typeName: String(reflecting: Configuration.self)
        )
    }
    return try lowerWidgetConfiguration(configuration.body)
}
