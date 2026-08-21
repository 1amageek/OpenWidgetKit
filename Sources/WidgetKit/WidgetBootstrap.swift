import OpenWidgetRuntime
import SwiftUI
#if os(Windows)
import OpenWidgetWindowsRuntime
#endif

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
@available(tvOS, unavailable)
extension Widget {
    @MainActor
    @preconcurrency
    public static func main() async {
        do {
#if os(Windows)
            WidgetRuntimeComposition.installBootstrap(
                try WindowsWidgetRuntimeBootstrap.defaultBootstrap()
            )
#endif
            try await WidgetRuntimeComposition.run(
                definitions: lowerWidget(Self.init())
            )
        } catch {
            WidgetRuntimeComposition.report(
                .operationFailed(
                    instanceID: nil,
                    kind: nil,
                    generation: nil,
                    operation: .startup,
                    cause: WidgetRuntimeFailureCode(error)
                )
            )
            fatalError("Widget runtime startup failed.")
        }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
extension WidgetBundle {
    @MainActor
    @preconcurrency
    public static func main() async {
        do {
#if os(Windows)
            WidgetRuntimeComposition.installBootstrap(
                try WindowsWidgetRuntimeBootstrap.defaultBootstrap()
            )
#endif
            try await WidgetRuntimeComposition.run(
                definitions: lowerWidgetBundle(Self.init())
            )
        } catch {
            WidgetRuntimeComposition.report(
                .operationFailed(
                    instanceID: nil,
                    kind: nil,
                    generation: nil,
                    operation: .startup,
                    cause: WidgetRuntimeFailureCode(error)
                )
            )
            fatalError("Widget runtime startup failed.")
        }
    }
}
