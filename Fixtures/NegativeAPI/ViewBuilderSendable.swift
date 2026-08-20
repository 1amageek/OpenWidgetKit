import SwiftUI

private func requireSendable<Value: Sendable>(_: Value.Type) {}

public func rejectViewBuilderSendableConformance() {
    requireSendable(ViewBuilder.self)
}
