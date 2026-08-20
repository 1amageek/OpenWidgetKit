package protocol RuntimeWidgetHost: Sendable {
    // The host must advance this fence monotonically and must not commit an
    // update whose generation is older than the latest fence for the instance.
    func invalidate(instanceID: String, generation: UInt64) async throws

    func apply(_ update: RuntimeWidgetUpdate) async throws

    // Removal advances the same generation fence and rejects all updates from
    // that lifetime through the removal generation, including suspended applies.
    // A recreated host instance may establish a strictly newer generation.
    func remove(instanceID: String, generation: UInt64) async throws
}
