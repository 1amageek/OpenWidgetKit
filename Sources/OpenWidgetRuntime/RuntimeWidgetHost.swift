package protocol RuntimeWidgetHost: Sendable {
    // The host must advance this fence monotonically and must not commit an
    // update whose generation is older than the latest fence for the instance.
    func invalidate(instanceID: String, generation: UInt64) async throws

    func apply(_ update: RuntimeWidgetUpdate) async throws

    // Removal advances the same generation fence and permanently rejects all
    // updates through that generation, including already suspended applies.
    func remove(instanceID: String, generation: UInt64) async throws
}
