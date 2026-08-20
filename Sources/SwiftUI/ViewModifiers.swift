import OpenWidgetRuntime

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension View {
    nonisolated public func padding(_ insets: EdgeInsets) -> some View {
        ModifiedWidgetView(
            content: self,
            modifier: .padding(edges: .all, insets: insets.widgetValue)
        )
    }

    nonisolated public func padding(
        _ edges: Edge.Set = .all,
        _ length: CGFloat? = nil
    ) -> some View {
        let insets = length.map {
            WidgetInsets(top: $0, leading: $0, bottom: $0, trailing: $0)
        }
        return ModifiedWidgetView(
            content: self,
            modifier: .padding(edges: edges.widgetValue, insets: insets)
        )
    }

    nonisolated public func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    nonisolated public func frame(
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        ModifiedWidgetView(
            content: self,
            modifier: .frame(
                WidgetFrame(
                    minWidth: width,
                    idealWidth: width,
                    maxWidth: width,
                    minHeight: height,
                    idealHeight: height,
                    maxHeight: height,
                    alignment: alignment.widgetValue
                )
            )
        )
    }

    nonisolated public func frame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil,
        alignment: Alignment = .center
    ) -> some View {
        ModifiedWidgetView(
            content: self,
            modifier: .frame(
                WidgetFrame(
                    minWidth: minWidth,
                    idealWidth: idealWidth,
                    maxWidth: maxWidth,
                    minHeight: minHeight,
                    idealHeight: idealHeight,
                    maxHeight: maxHeight,
                    alignment: alignment.widgetValue
                )
            )
        )
    }

    nonisolated public func font(_ font: Font?) -> some View {
        ModifiedWidgetView(content: self, modifier: .font(font?.widgetValue))
    }

    nonisolated public func foregroundColor(_ color: Color?) -> some View {
        ModifiedWidgetView(
            content: self,
            modifier: .foregroundColor(color?.widgetValue)
        )
    }

    nonisolated public func lineLimit(_ number: Int?) -> some View {
        ModifiedWidgetView(content: self, modifier: .lineLimit(number))
    }

    @_disfavoredOverload
    nonisolated public func background<Background>(
        _ background: Background,
        alignment: Alignment = .center
    ) -> some View where Background: View {
        BackgroundWidgetView(
            content: self,
            background: background,
            alignment: alignment
        )
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    nonisolated public func background<Background>(
        alignment: Alignment = .center,
        @ContentBuilder content: () -> Background
    ) -> some View where Background: View {
        BackgroundWidgetView(
            content: self,
            background: content(),
            alignment: alignment
        )
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    nonisolated public func background<Style>(
        _ style: Style,
        ignoresSafeAreaEdges edges: Edge.Set = .all
    ) -> some View where Style: ShapeStyle {
        BackgroundStyleWidgetView(
            content: self,
            style: style,
            ignoredEdges: edges
        )
    }

    nonisolated public func environment<Value>(
        _ keyPath: WritableKeyPath<EnvironmentValues, Value>,
        _ value: Value
    ) -> some View {
        EnvironmentWritingView(content: self, keyPath: keyPath, value: value)
    }

    nonisolated public func colorScheme(_ colorScheme: ColorScheme) -> some View {
        environment(\.colorScheme, colorScheme)
    }
}
