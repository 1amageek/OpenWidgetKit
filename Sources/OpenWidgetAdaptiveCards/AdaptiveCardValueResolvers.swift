import OpenFoundation
import OpenWidgetRuntime

package protocol AdaptiveCardResourceResolving: Sendable {
    func resolve(_ resource: WidgetResource) throws -> String
}

package protocol WidgetTextResolving: Sendable {
    func resolve(_ text: WidgetText) throws -> String
}

package struct BundleWidgetTextResolver: WidgetTextResolving {
    package init() {}

    package func resolve(_ text: WidgetText) throws -> String {
        switch text.storage {
        case .verbatim(let value):
            return value
        case .localized(
            let key,
            let tableName,
            let bundleIdentifier,
            _,
            let arguments
        ):
            let bundle: Bundle
            if let bundleIdentifier {
                let identifiedBundle = Bundle(identifier: bundleIdentifier)
                    ?? URL(string: bundleIdentifier).flatMap(Bundle.init(url:))
                guard let identifiedBundle else {
                    throw AdaptiveCardCompilationError.invalidLocalizedString(
                        "Bundle '\(bundleIdentifier)' could not be resolved."
                    )
                }
                bundle = identifiedBundle
            } else {
                bundle = .main
            }
            let format = bundle.localizedString(
                forKey: key,
                value: key,
                table: tableName
            )
            return try substitute(arguments, into: format)
        }
    }

    private func substitute(_ arguments: [String], into format: String) throws -> String {
        guard !arguments.isEmpty else { return format }
        var result = ""
        var argumentIndex = 0
        var index = format.startIndex
        while index < format.endIndex {
            let character = format[index]
            guard character == "%" else {
                result.append(character)
                index = format.index(after: index)
                continue
            }
            let nextIndex = format.index(after: index)
            guard nextIndex < format.endIndex else {
                throw AdaptiveCardCompilationError.invalidLocalizedString(
                    "A localized format ends with an incomplete placeholder."
                )
            }
            let next = format[nextIndex]
            if next == "%" {
                result.append("%")
            } else if next == "@" {
                guard argumentIndex < arguments.count else {
                    throw AdaptiveCardCompilationError.invalidLocalizedString(
                        "A localized format has more placeholders than arguments."
                    )
                }
                result.append(arguments[argumentIndex])
                argumentIndex += 1
            } else {
                throw AdaptiveCardCompilationError.invalidLocalizedString(
                    "Only %@ and %% localized placeholders are supported."
                )
            }
            index = format.index(after: nextIndex)
        }
        guard argumentIndex == arguments.count else {
            throw AdaptiveCardCompilationError.invalidLocalizedString(
                "A localized format has fewer placeholders than arguments."
            )
        }
        return result
    }
}
