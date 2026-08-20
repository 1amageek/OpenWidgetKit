@testable import OpenWidgetWindowsRuntime
import Testing

struct WindowsWidgetBridgeStatusTests {
    @Test
    func preservesTypedABIErrorSemantics() {
        #expect(
            WindowsWidgetBridgeStatus.error(code: 0, message: "") == nil
        )
        #expect(
            WindowsWidgetBridgeStatus.error(
                code: 3,
                message: "The provider library is unavailable."
            ) == WindowsWidgetHostError.bridgeUnavailable(
                "The provider library is unavailable."
            )
        )
        #expect(
            WindowsWidgetBridgeStatus.error(
                code: 7,
                message: "Stale.",
                instanceID: "instance",
                generation: 42
            ) == WindowsWidgetHostError.staleGeneration(
                instanceID: "instance",
                generation: 42
            )
        )
        #expect(
            WindowsWidgetBridgeStatus.error(
                code: 8,
                message: "Shutting down."
            ) == WindowsWidgetHostError.shuttingDown
        )
        #expect(
            WindowsWidgetBridgeStatus.error(
                code: 9,
                message: "Internal failure."
            ) == WindowsWidgetHostError.hostRejected(
                code: 9,
                message: "Internal failure."
            )
        )
    }
}
