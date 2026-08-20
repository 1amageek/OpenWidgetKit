package enum WindowsWidgetBridgeStatus {
    // These raw values are the stable C ABI declared by OWKStatusCode. Keeping
    // the translation here prevents loader details from leaking into the host.
    private static let success: Int32 = 0
    private static let platformUnavailable: Int32 = 2
    private static let libraryLoadFailed: Int32 = 3
    private static let symbolMissing: Int32 = 4
    private static let staleGeneration: Int32 = 7
    private static let shuttingDown: Int32 = 8

    package static func error(
        code: Int32,
        message: String,
        instanceID: String? = nil,
        generation: UInt64? = nil
    ) -> WindowsWidgetHostError? {
        guard code != success else { return nil }
        switch code {
        case platformUnavailable, libraryLoadFailed, symbolMissing:
            return .bridgeUnavailable(message)
        case staleGeneration:
            guard let instanceID, let generation else {
                return .hostRejected(code: code, message: message)
            }
            return .staleGeneration(
                instanceID: instanceID,
                generation: generation
            )
        case shuttingDown:
            return .shuttingDown
        default:
            return .hostRejected(code: code, message: message)
        }
    }
}
