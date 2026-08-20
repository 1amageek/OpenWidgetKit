import COpenWidgetWindowsBridge
import OpenFoundation
import OpenWidgetRuntime

package final class DynamicWindowsWidgetBridge: WindowsWidgetBridge, Sendable {
    // The provider handle is owned by this object, destroyed exactly once in
    // deinit, and never dereferenced by Swift. The C++ provider synchronizes all
    // concurrent operations that receive this immutable opaque identity.
    private struct ProviderHandle: @unchecked Sendable {
        let pointer: OpaquePointer
    }

    // The retained callback owner is released only after the provider has been
    // destroyed, so callbacks cannot observe a dangling Swift context.
    private struct CallbackContext: @unchecked Sendable {
        let pointer: UnsafeMutableRawPointer
    }

    fileprivate final class CallbackOwner: Sendable {
        let eventSink: @Sendable (WindowsWidgetProviderEvent) -> Void
        let diagnosticSink: @Sendable (WindowsWidgetBridgeDiagnostic) -> Void

        init(
            eventSink: @escaping @Sendable (WindowsWidgetProviderEvent) -> Void,
            diagnosticSink: @escaping @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
        ) {
            self.eventSink = eventSink
            self.diagnosticSink = diagnosticSink
        }
    }

    private let handle: ProviderHandle
    private let callbackContext: CallbackContext

    package init(
        libraryPath: String,
        classID: String,
        eventSink: @escaping @Sendable (WindowsWidgetProviderEvent) -> Void,
        diagnosticSink: @escaping @Sendable (WindowsWidgetBridgeDiagnostic) -> Void
    ) throws {
        let callbackOwner = CallbackOwner(
            eventSink: eventSink,
            diagnosticSink: diagnosticSink
        )
        let retainedContext = Unmanaged.passRetained(callbackOwner).toOpaque()
        var openedHandle: OpaquePointer?
        do {
            try Self.withByteSlice(libraryPath) { librarySlice in
                try Self.withByteSlice(classID) { classIDSlice in
                    var configuration = OWKProviderConfiguration(
                        class_id: classIDSlice,
                        callbacks: OWKCallbacks(
                            context: retainedContext,
                            on_event: openWidgetEventCallback,
                            on_diagnostic: openWidgetDiagnosticCallback
                        )
                    )
                    let result = owk_bridge_open(
                        librarySlice,
                        &configuration,
                        &openedHandle
                    )
                    try Self.requireSuccess(result)
                }
            }
        } catch {
            Unmanaged<CallbackOwner>.fromOpaque(retainedContext).release()
            throw error
        }
        guard let openedHandle else {
            Unmanaged<CallbackOwner>.fromOpaque(retainedContext).release()
            throw WindowsWidgetHostError.bridgeUnavailable(
                "The bridge returned success without a provider handle."
            )
        }
        handle = ProviderHandle(pointer: openedHandle)
        callbackContext = CallbackContext(pointer: retainedContext)
    }

    deinit {
        owk_bridge_close(handle.pointer)
        Unmanaged<CallbackOwner>.fromOpaque(callbackContext.pointer).release()
    }

    package func runBlocking() throws {
        try Self.requireSuccess(owk_bridge_run(handle.pointer))
    }

    package func requestShutdown() throws {
        try Self.requireSuccess(owk_bridge_request_shutdown(handle.pointer))
    }

    package func completeShutdown() throws {
        try Self.requireSuccess(owk_bridge_complete_shutdown(handle.pointer))
    }

    package func invalidate(instanceID: String, generation: UInt64) throws {
        try Self.withByteSlice(instanceID) { instanceSlice in
            try Self.requireSuccess(
                owk_bridge_invalidate(handle.pointer, instanceSlice, generation),
                instanceID: instanceID,
                generation: generation
            )
        }
    }

    package func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws {
        try Self.withByteSlice(instanceID) { instanceSlice in
            try Self.withOptionalByteSlice(templateJSON) { templateSlice in
                try Self.withByteSlice(dataJSON) { dataSlice in
                    try Self.withByteSlice(customState) { customStateSlice in
                        try Self.requireSuccess(
                            owk_bridge_update(
                                handle.pointer,
                                instanceSlice,
                                generation,
                                templateSlice,
                                dataSlice,
                                customStateSlice
                            ),
                            instanceID: instanceID,
                            generation: generation
                        )
                    }
                }
            }
        }
    }

    package func remove(instanceID: String, generation: UInt64) throws {
        try Self.withByteSlice(instanceID) { instanceSlice in
            try Self.requireSuccess(
                owk_bridge_remove(handle.pointer, instanceSlice, generation),
                instanceID: instanceID,
                generation: generation
            )
        }
    }

    private static func withByteSlice<Result>(
        _ value: String,
        _ body: (OWKByteSlice) throws -> Result
    ) rethrows -> Result {
        let bytes = Array(value.utf8)
        return try bytes.withUnsafeBufferPointer { buffer in
            try body(
                OWKByteSlice(data: buffer.baseAddress, count: buffer.count)
            )
        }
    }

    private static func withOptionalByteSlice<Result>(
        _ value: String?,
        _ body: (OWKByteSlice) throws -> Result
    ) rethrows -> Result {
        guard let value else {
            return try body(OWKByteSlice(data: nil, count: 0))
        }
        return try withByteSlice(value, body)
    }

    private static func requireSuccess(
        _ result: OWKResult,
        instanceID: String? = nil,
        generation: UInt64? = nil
    ) throws {
        defer { release(result.message) }
        guard result.code != 0 else { return }
        let message = try decode(result.message.bytes)
        if let error = WindowsWidgetBridgeStatus.error(
            code: result.code,
            message: message,
            instanceID: instanceID,
            generation: generation
        ) {
            throw error
        }
    }

    private static func release(_ bytes: OWKOwnedBytes) {
        bytes.release_owner?(bytes.owner)
    }

    private static func decode(_ bytes: OWKByteSlice) throws -> String {
        guard bytes.count > 0 else { return "" }
        guard let data = bytes.data,
              let value = String(
                  bytes: UnsafeBufferPointer(start: data, count: bytes.count),
                  encoding: .utf8
              ) else {
            throw WindowsWidgetHostError.invalidBridgeUTF8
        }
        return value
    }
}

private func openWidgetEventCallback(
    _ context: UnsafeMutableRawPointer?,
    _ eventPointer: UnsafePointer<OWKWidgetEvent>?
) {
    guard let eventPointer else { return }
    let event = eventPointer.pointee
    defer { event.release_owner?(event.owner) }
    guard let context else { return }
    let owner = Unmanaged<DynamicWindowsWidgetBridge.CallbackOwner>
        .fromOpaque(context)
        .takeUnretainedValue()
    do {
        let instanceID = try decodeBridgeString(event.widget_id)
        let definitionID = try decodeBridgeString(event.definition_id)
        let customState = try decodeBridgeString(event.custom_state)
        let actionVerb = try decodeBridgeString(event.action_verb)
        let actionData = try decodeBridgeString(event.action_data)
        let value: WindowsWidgetProviderEvent
        switch event.kind {
        case 1:
            value = .create(
                instanceID: instanceID,
                kind: definitionID,
                family: try runtimeFamily(event.widget_size),
                isActive: event.is_active != 0
            )
        case 2:
            value = .delete(instanceID: instanceID, customState: customState)
        case 3:
            value = .activate(instanceID: instanceID)
        case 4:
            value = .deactivate(instanceID: instanceID)
        case 5:
            value = .contextChanged(
                instanceID: instanceID,
                family: try runtimeFamily(event.widget_size),
                isActive: event.is_active != 0
            )
        case 6:
            value = .actionInvoked(
                instanceID: instanceID,
                verb: actionVerb,
                data: actionData,
                customState: customState
            )
        case 7:
            value = .recover(
                instanceID: instanceID,
                kind: definitionID,
                family: try runtimeFamily(event.widget_size),
                isActive: event.is_active != 0,
                hasRetainedHostContent: !customState.isEmpty
            )
        case 8:
            value = .shutdownRequested
        default:
            throw WindowsWidgetHostError.hostRejected(
                code: Int32(event.kind),
                message: "The bridge emitted an unknown event kind."
            )
        }
        owner.eventSink(value)
    } catch {
        owner.diagnosticSink(
            WindowsWidgetBridgeDiagnostic(
                code: -1,
                message: String(describing: error)
            )
        )
    }
}

private func openWidgetDiagnosticCallback(
    _ context: UnsafeMutableRawPointer?,
    _ code: Int32,
    _ message: OWKOwnedBytes
) {
    defer { message.release_owner?(message.owner) }
    guard let context else { return }
    let owner = Unmanaged<DynamicWindowsWidgetBridge.CallbackOwner>
        .fromOpaque(context)
        .takeUnretainedValue()
    do {
        owner.diagnosticSink(
            WindowsWidgetBridgeDiagnostic(
                code: code,
                message: try decodeBridgeString(message.bytes)
            )
        )
    } catch {
        owner.diagnosticSink(
            WindowsWidgetBridgeDiagnostic(
                code: code,
                message: "The bridge diagnostic was not valid UTF-8."
            )
        )
    }
}

private func decodeBridgeString(_ bytes: OWKByteSlice) throws -> String {
    guard bytes.count > 0 else { return "" }
    guard let data = bytes.data,
          let value = String(
              bytes: UnsafeBufferPointer(start: data, count: bytes.count),
              encoding: .utf8
          ) else {
        throw WindowsWidgetHostError.invalidBridgeUTF8
    }
    return value
}

private func runtimeFamily(_ rawValue: Int32) throws -> RuntimeWidgetFamily {
    switch rawValue {
    case 1: .systemSmall
    case 2: .systemMedium
    case 3: .systemLarge
    default:
        throw WindowsWidgetHostError.hostRejected(
            code: rawValue,
            message: "The bridge emitted an unsupported widget size."
        )
    }
}
