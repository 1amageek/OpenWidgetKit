package protocol WidgetRuntimeControl: Sendable {
    func reloadTimelines(ofKind kind: String)
    func reloadAllTimelines()
    func getCurrentConfigurations(
        _ completion: @escaping @Sendable (
            Result<[RuntimeWidgetInfo], WidgetRuntimeError>
        ) -> Void
    )
}

extension WidgetRuntimeService: WidgetRuntimeControl {
    nonisolated package func reloadTimelines(ofKind kind: String) {
        Task { await reload(kind: kind) }
    }

    nonisolated package func reloadAllTimelines() {
        Task { await reloadAll() }
    }

    nonisolated package func getCurrentConfigurations(
        _ completion: @escaping @Sendable (
            Result<[RuntimeWidgetInfo], WidgetRuntimeError>
        ) -> Void
    ) {
        Task {
            completion(.success(await currentConfigurations()))
        }
    }
}
