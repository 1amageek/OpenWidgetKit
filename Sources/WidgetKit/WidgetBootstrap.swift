import OpenWidgetRuntime
import SwiftUI

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
@available(tvOS, unavailable)
extension Widget {
    @MainActor
    @preconcurrency
    public static func main() {
        do {
            try WidgetRuntimeComposition.run(
                definitions: lowerWidget(Self.init())
            )
        } catch {
            fatalError("Widget runtime startup failed: \(error)")
        }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetBundle {
    @MainActor
    @preconcurrency
    public static func main() {
        do {
            try WidgetRuntimeComposition.run(
                definitions: lowerWidgetBundle(Self.init())
            )
        } catch {
            fatalError("Widget runtime startup failed: \(error)")
        }
    }
}
