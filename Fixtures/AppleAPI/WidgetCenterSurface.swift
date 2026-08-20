import SwiftUI
import WidgetKit

@available(macOS 11.0, iOS 14.0, watchOS 9.0, *)
public func verifyAppleWidgetCenterSurface(kind: String) {
    let center = WidgetCenter.shared

    center.getCurrentConfigurations { result in
        switch result {
        case .success(let configurations):
            for configuration in configurations {
                let _: WidgetFamily = configuration.family
                let _: String = configuration.kind
                _ = configuration.configuration
            }
        case .failure(let error):
            _ = error
        }
    }
    center.reloadTimelines(ofKind: kind)
    center.reloadAllTimelines()

    let _: String = WidgetCenter.UserInfoKey.kind
    let _: String = WidgetCenter.UserInfoKey.family
    let _: String = WidgetCenter.UserInfoKey.activityID
}
