@MainActor
package final class WidgetIdentityStore {
    private struct Key: Hashable {
        let namespace: WidgetNodeID
        let value: AnyHashable
    }

    private struct EvaluationFrame {
        let startingIdentifier: UInt64
        var insertedKeys: [Key] = []
        var newlyUsedKeys: [Key] = []
    }

    private var identifiers: [Key: UInt64] = [:]
    private var nextIdentifier: UInt64 = 0
    private var evaluationFrames: [EvaluationFrame] = []
    private var usedKeys: Set<Key>?

    package init() {}

    package var retainedIdentifierCount: Int {
        identifiers.count
    }

    package func withEvaluation<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        let isOutermost = evaluationFrames.isEmpty
        if isOutermost {
            usedKeys = []
        }
        evaluationFrames.append(
            EvaluationFrame(startingIdentifier: nextIdentifier)
        )
        do {
            let result = try operation()
            let completedFrame = evaluationFrames.removeLast()
            if isOutermost {
                let retainedKeys = usedKeys ?? []
                identifiers = identifiers.filter { retainedKeys.contains($0.key) }
                clearEvaluationState()
            } else {
                evaluationFrames[evaluationFrames.index(before: evaluationFrames.endIndex)]
                    .insertedKeys.append(contentsOf: completedFrame.insertedKeys)
                evaluationFrames[evaluationFrames.index(before: evaluationFrames.endIndex)]
                    .newlyUsedKeys.append(contentsOf: completedFrame.newlyUsedKeys)
            }
            return result
        } catch {
            let failedFrame = evaluationFrames.removeLast()
            for key in failedFrame.insertedKeys {
                identifiers.removeValue(forKey: key)
            }
            for key in failedFrame.newlyUsedKeys {
                usedKeys?.remove(key)
            }
            nextIdentifier = failedFrame.startingIdentifier
            if isOutermost {
                clearEvaluationState()
            }
            throw error
        }
    }

    package func identifier<ID: Hashable>(
        for value: ID,
        namespace: WidgetNodeID
    ) throws -> UInt64 {
        let key = Key(namespace: namespace, value: AnyHashable(value))
        if usedKeys?.insert(key).inserted == true {
            evaluationFrames[evaluationFrames.index(before: evaluationFrames.endIndex)]
                .newlyUsedKeys.append(key)
        }
        if let identifier = identifiers[key] {
            return identifier
        }

        guard nextIdentifier < UInt64.max else {
            throw WidgetRuntimeError.identitySpaceExhausted
        }
        let identifier = nextIdentifier
        nextIdentifier += 1
        identifiers[key] = identifier
        if !evaluationFrames.isEmpty {
            evaluationFrames[evaluationFrames.index(before: evaluationFrames.endIndex)]
                .insertedKeys.append(key)
        }
        return identifier
    }

    private func clearEvaluationState() {
        usedKeys = nil
        evaluationFrames.removeAll(keepingCapacity: true)
    }
}
