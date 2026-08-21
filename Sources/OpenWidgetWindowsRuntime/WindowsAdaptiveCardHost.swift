import OpenFoundation
import OpenWidgetAdaptiveCards
import OpenWidgetRuntime

package actor WindowsAdaptiveCardHost: RuntimeWidgetHost {
    private struct Fence: Sendable {
        var generation: UInt64
        var isDeleted: Bool
        var structureIdentity: String?
        var actionRevision: UInt64
        var customState: String?
        var actions: [String: AdaptiveCardActionBinding]
        var inFlightActions: Set<WidgetActionID>
    }

    private let compiler: AdaptiveCardCompiler
    private let bridge: any WindowsWidgetBridge
    private let actionSessionID: String
    private var fences: [String: Fence] = [:]

    package init(
        compiler: AdaptiveCardCompiler,
        bridge: any WindowsWidgetBridge,
        actionSessionID: String = UUID().uuidString
    ) {
        self.compiler = compiler
        self.bridge = bridge
        self.actionSessionID = actionSessionID
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
            structureIdentity: structureIdentity,
            actionRevision: 0,
            customState: nil,
            actions: [:],
            inFlightActions: []
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
        var actions: [String: AdaptiveCardActionBinding] = [:]
        for binding in payload.actionBindings {
            guard actions.updateValue(binding, forKey: binding.verb) == nil else {
                throw WindowsWidgetHostError.duplicateAction(
                    instanceID: update.instanceID,
                    verb: binding.verb
                )
            }
        }
        guard fence.actionRevision < UInt64.max else {
            throw WindowsWidgetHostError.actionRevisionExhausted(
                instanceID: update.instanceID
            )
        }
        let actionRevision = fence.actionRevision + 1
        let customState = Self.customState(
            sessionID: actionSessionID,
            instanceID: update.instanceID,
            generation: update.generation,
            actionRevision: actionRevision,
            structureIdentity: payload.structureIdentity
        )
        // Reserve the externally visible revision before crossing the bridge.
        // A bridge failure may occur after the host accepted the update, so a
        // later attempt must never reuse the same custom-state token.
        fence.actionRevision = actionRevision
        fences[update.instanceID] = fence
        try bridge.update(
            instanceID: update.instanceID,
            generation: update.generation,
            templateJSON: templateJSON,
            dataJSON: payload.dataJSON,
            customState: customState
        )
        fence.structureIdentity = payload.structureIdentity
        fence.customState = customState
        fence.actions = actions
        fence.inFlightActions.removeAll(keepingCapacity: true)
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
            structureIdentity: structureIdentity,
            actionRevision: 0,
            customState: nil,
            actions: [:],
            inFlightActions: []
        )
        try bridge.remove(instanceID: instanceID, generation: generation)
    }

    package func beginAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) async throws -> WindowsWidgetActionExecution {
        guard var fence = fences[instanceID], !fence.isDeleted else {
            throw WindowsWidgetHostError.unknownInstance(instanceID)
        }
        guard customState == fence.customState else {
            throw WindowsWidgetHostError.staleAction(
                instanceID: instanceID,
                verb: verb
            )
        }
        guard let binding = fence.actions[verb] else {
            throw WindowsWidgetHostError.unknownAction(
                instanceID: instanceID,
                verb: verb
            )
        }
        try validateActionPayload(
            data,
            expectedVerb: binding.verb,
            instanceID: instanceID
        )
        let actionID = binding.action.id
        guard fence.inFlightActions.insert(actionID).inserted else {
            throw WindowsWidgetHostError.duplicateAction(
                instanceID: instanceID,
                verb: verb
            )
        }
        let generation = fence.generation
        let action = binding.action
        fences[instanceID] = fence
        return WindowsWidgetActionExecution { [weak self, action] in
            do {
                try await action.perform()
            } catch {
                await self?.finishAction(
                    instanceID: instanceID,
                    actionID: actionID,
                    generation: generation,
                    customState: customState
                )
                throw error
            }
            guard let self else {
                throw WindowsWidgetHostError.shuttingDown
            }
            return try await self.completeAction(
                instanceID: instanceID,
                verb: verb,
                actionID: actionID,
                generation: generation,
                customState: customState
            )
        }
    }

    nonisolated package func performAction(
        instanceID: String,
        verb: String,
        data: String,
        customState: String
    ) async throws -> UInt64 {
        let execution = try await beginAction(
            instanceID: instanceID,
            verb: verb,
            data: data,
            customState: customState
        )
        return try await execution.value()
    }

    private func completeAction(
        instanceID: String,
        verb: String,
        actionID: WidgetActionID,
        generation: UInt64,
        customState: String
    ) throws -> UInt64 {
        finishAction(
            instanceID: instanceID,
            actionID: actionID,
            generation: generation,
            customState: customState
        )
        guard let current = fences[instanceID],
              !current.isDeleted,
              current.generation == generation,
              current.customState == customState else {
            throw WindowsWidgetHostError.staleAction(
                instanceID: instanceID,
                verb: verb
            )
        }
        return generation
    }

    private func finishAction(
        instanceID: String,
        actionID: WidgetActionID,
        generation: UInt64,
        customState: String
    ) {
        guard var fence = fences[instanceID],
              fence.generation == generation,
              fence.customState == customState else {
            return
        }
        fence.inFlightActions.remove(actionID)
        fences[instanceID] = fence
    }

    private func validateActionPayload(
        _ data: String,
        expectedVerb: String,
        instanceID: String
    ) throws {
        let decoded: Any
        do {
            decoded = try JSONSerialization.jsonObject(
                with: Data(data.utf8)
            )
        } catch {
            throw WindowsWidgetHostError.invalidActionPayload(
                instanceID: instanceID,
                verb: expectedVerb
            )
        }
        guard let object = decoded as? [String: Any],
              object.count == 1,
              let payloadID = object["openWidgetActionID"] as? String,
              payloadID == expectedVerb else {
            throw WindowsWidgetHostError.invalidActionPayload(
                instanceID: instanceID,
                verb: expectedVerb
            )
        }
    }

    private static func customState(
        sessionID: String,
        instanceID: String,
        generation: UInt64,
        actionRevision: UInt64,
        structureIdentity: String
    ) -> String {
        [
            "openwidget-state-v2",
            "session:\(sessionID.utf8.count):\(sessionID)",
            "instance:\(instanceID.utf8.count):\(instanceID)",
            "generation:\(generation)",
            "revision:\(actionRevision)",
            "structure:\(structureIdentity)"
        ].joined(separator: "|")
    }
}

extension WindowsAdaptiveCardHost: WindowsWidgetActionHost {}
