import OpenCoreGraphics
import WidgetKit

@available(iOS 14.0, macOS 11.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
public func passWidgetGeometryToCoreGraphics(
    _ context: TimelineProviderContext,
    graphicsContext: CGContext,
    point: CGPoint,
    rect: CGRect
) -> CGSize {
    let widgetSize: CGSize = context.displaySize
    let translatedPoint = graphicsContext.convertToDeviceSpace(point)
    let translatedRect = graphicsContext.convertToDeviceSpace(rect)

    _ = translatedPoint
    _ = translatedRect

    return graphicsContext.convertToDeviceSpace(widgetSize)
}
