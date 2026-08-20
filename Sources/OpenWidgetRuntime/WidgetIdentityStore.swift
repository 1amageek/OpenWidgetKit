@MainActor
package final class WidgetIdentityStore {
    private struct Key: Hashable {
        let namespace: WidgetNodeID
        let value: AnyHashable
    }

    private var identifiers: [Key: UInt64] = [:]
    private var nextIdentifier: UInt64 = 0

    package init() {}

    package func identifier<ID: Hashable>(
        for value: ID,
        namespace: WidgetNodeID
    ) -> UInt64 {
        let key = Key(namespace: namespace, value: AnyHashable(value))
        if let identifier = identifiers[key] {
            return identifier
        }

        let identifier = nextIdentifier
        nextIdentifier &+= 1
        identifiers[key] = identifier
        return identifier
    }
}
