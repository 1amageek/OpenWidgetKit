import Foundation
import SwiftUI
import WidgetKit

@available(macOS 11.0, iOS 14.0, *)
public func verifyAppleTimelineProviderContextCFCGSurface(
    _ context: TimelineProviderContext,
    colorSchemes: TimelineProviderContext.EnvironmentVariants
) {
    let _: CGSize = context.displaySize
    let _: [ColorScheme]? = colorSchemes[keyPath: \.colorScheme]
    let _: [ColorScheme]? = colorSchemes.colorScheme
}
