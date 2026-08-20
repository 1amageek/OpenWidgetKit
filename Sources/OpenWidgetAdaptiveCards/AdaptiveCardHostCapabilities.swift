package struct AdaptiveCardHostCapabilities: Equatable, Hashable, Sendable {
    package let schemaVersion: String
    package let compilerContractVersion: Int

    package init(
        schemaVersion: String = "1.6",
        compilerContractVersion: Int = 1
    ) {
        self.schemaVersion = schemaVersion
        self.compilerContractVersion = compilerContractVersion
    }
}
