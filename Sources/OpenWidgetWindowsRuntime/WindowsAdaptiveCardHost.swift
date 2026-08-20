import OpenWidgetAdaptiveCards
import OpenWidgetRuntime

package actor WindowsAdaptiveCardHost: RuntimeWidgetHost {
    private struct Fence: Sendable {
        var generation: UInt64
        var isDeleted: Bool
        var structureIdentity: String?
    }

    private let compiler: AdaptiveCardCompiler
    private let bridge: any WindowsWidgetBridge
    private var fences: [String: Fence] = [:]

    package init(
        compiler: AdaptiveCardCompiler,
        bridge: any WindowsWidgetBridge
    ) {
        self.compiler = compiler
        self.bridge = bridge
    }

    package func invalidate(instanceID: String, generation: UInt64) throws {
        var structureIdentity = fences[instanceID]?.structureIdentity
        if let fence = fences[instanceID] {
            guard generation >= fence.generation,
                  !fence.isDeleted || generation > fence.generation else {
                throw WindowsWidgetHostError.staleGeneration(
                    instanceID: instanceID,
                    generation: generation
                )
            }
            if fence.isDeleted {
                // A recreated widget has no host-accepted template from its
                // previous lifetime, even when its semantic structure matches.
                structureIdentity = nil
            }
        }
        let nextFence = Fence(
            generation: generation,
            isDeleted: false,
            structureIdentity: structureIdentity
        )
        try bridge.invalidate(instanceID: instanceID, generation: generation)
        fences[instanceID] = nextFence
    }

    package func apply(_ update: RuntimeWidgetUpdate) throws {
        guard var fence = fences[update.instanceID],
              !fence.isDeleted,
              fence.generation == update.generation else {
            throw WindowsWidgetHostError.staleGeneration(
                instanceID: update.instanceID,
                generation: update.generation
            )
        }
        let payload = try compiler.compile(update)
        let templateJSON = fence.structureIdentity == payload.structureIdentity
            ? nil
            : payload.templateJSON
        try bridge.update(
            instanceID: update.instanceID,
            generation: update.generation,
            templateJSON: templateJSON,
            dataJSON: payload.dataJSON,
            customState: payload.structureIdentity
        )
        fence.structureIdentity = payload.structureIdentity
        fences[update.instanceID] = fence
    }

    package func remove(instanceID: String, generation: UInt64) throws {
        let structureIdentity = fences[instanceID]?.structureIdentity
        if let fence = fences[instanceID], generation < fence.generation {
            throw WindowsWidgetHostError.staleGeneration(
                instanceID: instanceID,
                generation: generation
            )
        }
        // Deletion is fail-closed: the host callback already established that
        // this lifetime ended, so a bridge cleanup failure must not reopen it.
        fences[instanceID] = Fence(
            generation: generation,
            isDeleted: true,
            structureIdentity: structureIdentity
        )
        try bridge.remove(instanceID: instanceID, generation: generation)
    }
}
