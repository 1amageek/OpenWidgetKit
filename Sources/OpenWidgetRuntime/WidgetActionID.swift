package struct WidgetActionID: Hashable, Sendable {
    package let rawValue: String

    package init(rawValue: String) {
        self.rawValue = rawValue
    }

    package init(nodeID: WidgetNodeID) {
        var components = ["openwidget", "action", "v1"]
        components.reserveCapacity(nodeID.components.count + 3)
        for component in nodeID.components {
            switch component {
            case .structural(let index):
                components.append("s:\(index)")
            case .keyed(let identifier):
                components.append("k:\(identifier)")
            case .role(let role):
                components.append("r:\(role.utf8.count):\(role)")
            }
        }
        rawValue = components.joined(separator: "|")
    }
}
