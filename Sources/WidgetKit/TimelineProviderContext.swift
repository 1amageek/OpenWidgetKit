import OpenFoundation
import SwiftUI

public struct TimelineProviderContext {
    @dynamicMemberLookup
    public struct EnvironmentVariants {
        private let values: [EnvironmentValues]

        package init(values: [EnvironmentValues]) {
            self.values = values
        }

        public subscript<T>(
            dynamicMember keyPath: WritableKeyPath<EnvironmentValues, T>
        ) -> [T]? {
            self[keyPath: keyPath]
        }

        public subscript<T>(
            keyPath keyPath: WritableKeyPath<EnvironmentValues, T>
        ) -> [T]? {
            guard !values.isEmpty else { return nil }
            return values.map { $0[keyPath: keyPath] }
        }
    }

    public let environmentVariants: EnvironmentVariants
    public let family: WidgetFamily
    public let isPreview: Bool
    public let displaySize: CGSize

    package init(
        family: WidgetFamily,
        isPreview: Bool,
        displaySize: CGSize,
        environmentVariants: EnvironmentVariants = EnvironmentVariants(values: [])
    ) {
        self.environmentVariants = environmentVariants
        self.family = family
        self.isPreview = isPreview
        self.displaySize = displaySize
    }
}
