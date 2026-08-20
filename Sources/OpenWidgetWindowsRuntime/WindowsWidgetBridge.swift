package protocol WindowsWidgetBridge: Sendable {
    func runBlocking() throws
    func requestShutdown() throws
    func completeShutdown() throws
    func invalidate(instanceID: String, generation: UInt64) throws
    func update(
        instanceID: String,
        generation: UInt64,
        templateJSON: String?,
        dataJSON: String,
        customState: String
    ) throws
    func remove(instanceID: String, generation: UInt64) throws
}
