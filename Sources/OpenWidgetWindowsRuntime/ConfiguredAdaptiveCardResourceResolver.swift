import OpenWidgetAdaptiveCards
import OpenWidgetRuntime

package struct ConfiguredAdaptiveCardResourceResolver: AdaptiveCardResourceResolving {
    private let configuration: OpenWidgetProviderConfiguration

    package init(configuration: OpenWidgetProviderConfiguration) {
        self.configuration = configuration
    }

    package func resolve(_ resource: WidgetResource) throws -> String {
        switch resource {
        case .namedImage(let name, let bundleIdentifier):
            guard bundleIdentifier == nil else {
                throw AdaptiveCardCompilationError.unresolvedResource(
                    "Windows package resources cannot resolve an Apple bundle identifier."
                )
            }
            guard let configured = configuration.resource(named: name) else {
                throw AdaptiveCardCompilationError.unresolvedResource(
                    "Named image '\(name)' is absent from OpenWidgetProvider.json."
                )
            }
            return configured.uri
        case .systemImage(let name):
            throw AdaptiveCardCompilationError.unresolvedResource(
                "System image '\(name)' requires an explicit Windows asset mapping."
            )
        }
    }
}
