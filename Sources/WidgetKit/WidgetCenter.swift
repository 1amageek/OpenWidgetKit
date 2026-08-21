import OpenWidgetRuntime

@available(iOS 14.0, macOS 11.0, watchOS 9.0, visionOS 26.0, *)
@available(tvOS, unavailable)
public class WidgetCenter {
    // The singleton has no mutable instance state. Runtime state is stored in
    // WidgetRuntimeComposition's Mutex-protected composition boundary.
    nonisolated(unsafe) public static let shared = WidgetCenter()

    public struct UserInfoKey {
        public static let kind = "WGWidgetUserInfoKeyKind"
        public static let family = "WGWidgetUserInfoKeyFamily"
        public static let activityID = "WGWidgetUserInfoKeyActivityID"
    }

    private init() {}

    @preconcurrency
    public func getCurrentConfigurations(
        _ completion: @escaping @Sendable (
            Result<[WidgetInfo], any Error>
        ) -> Void
    ) {
        guard let control = WidgetRuntimeComposition.currentControl() else {
            WidgetRuntimeComposition.report(
                .controlUnavailable(
                    operation: .currentConfigurations,
                    kind: nil
                )
            )
            completion(.failure(WidgetRuntimeError.hostUnavailable))
            return
        }
        control.getCurrentConfigurations { result in
            switch result {
            case .success(let values):
                completion(
                    .success(values.map(WidgetInfo.init(runtimeValue:)))
                )
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func reloadTimelines(ofKind kind: String) {
        guard let control = WidgetRuntimeComposition.currentControl() else {
            WidgetRuntimeComposition.report(
                .controlUnavailable(
                    operation: .reloadTimelines,
                    kind: kind
                )
            )
            return
        }
        control.reloadTimelines(ofKind: kind)
    }

    public func reloadAllTimelines() {
        guard let control = WidgetRuntimeComposition.currentControl() else {
            WidgetRuntimeComposition.report(
                .controlUnavailable(
                    operation: .reloadAllTimelines,
                    kind: nil
                )
            )
            return
        }
        control.reloadAllTimelines()
    }
}
