import OpenWidgetRuntime

package struct AdaptiveCardActionBinding: Sendable {
    package let verb: String
    package let action: WidgetAction

    package init(
        verb: String,
        action: WidgetAction
    ) {
        self.verb = verb
        self.action = action
    }
}
