import OpenWidgetRuntime
import SwiftUI

@MainActor
private enum RuntimeConfigurationModifier {
    case supportedFamilies([RuntimeWidgetFamily])
    case displayName(WidgetText)
    case configurationDescription(WidgetText)

    func apply(
        to definition: RuntimeWidgetDefinition
    ) -> RuntimeWidgetDefinition {
        switch self {
        case .supportedFamilies(let families):
            definition.withSupportedFamilies(families)
        case .displayName(let displayName):
            definition.withDisplayName(displayName)
        case .configurationDescription(let description):
            definition.withConfigurationDescription(description)
        }
    }
}

@MainActor
private struct ModifiedWidgetConfiguration<Configuration>: WidgetConfiguration
where Configuration: WidgetConfiguration {
    typealias Body = Never

    let configuration: Configuration
    let modifier: RuntimeConfigurationModifier
}

extension ModifiedWidgetConfiguration: WidgetConfigurationLowering {
    func makeRuntimeWidgetDefinitions() throws -> [RuntimeWidgetDefinition] {
        try lowerWidgetConfiguration(configuration).map { modifier.apply(to: $0) }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetConfiguration {
    @MainActor
    @preconcurrency
    public func configurationDisplayName(
        _ displayName: Text
    ) -> some WidgetConfiguration {
        ModifiedWidgetConfiguration(
            configuration: self,
            modifier: .displayName(displayName.widgetValue)
        )
    }

    @MainActor
    @preconcurrency
    public func configurationDisplayName(
        _ displayNameKey: LocalizedStringKey
    ) -> some WidgetConfiguration {
        configurationDisplayName(Text(displayNameKey))
    }

    @_disfavoredOverload
    @MainActor
    @preconcurrency
    public func configurationDisplayName<Value>(
        _ displayName: Value
    ) -> some WidgetConfiguration where Value: StringProtocol {
        configurationDisplayName(Text(verbatim: String(displayName)))
    }

    @MainActor
    @preconcurrency
    public func description(
        _ description: Text
    ) -> some WidgetConfiguration {
        ModifiedWidgetConfiguration(
            configuration: self,
            modifier: .configurationDescription(description.widgetValue)
        )
    }

    @MainActor
    @preconcurrency
    public func description(
        _ descriptionKey: LocalizedStringKey
    ) -> some WidgetConfiguration {
        description(Text(descriptionKey))
    }

    @_disfavoredOverload
    @MainActor
    @preconcurrency
    public func description<Value>(
        _ description: Value
    ) -> some WidgetConfiguration where Value: StringProtocol {
        self.description(Text(verbatim: String(description)))
    }

    @MainActor
    @preconcurrency
    public func supportedFamilies(
        _ families: [WidgetFamily]
    ) -> some WidgetConfiguration {
        ModifiedWidgetConfiguration(
            configuration: self,
            modifier: .supportedFamilies(families.map(\.runtimeValue))
        )
    }
}
