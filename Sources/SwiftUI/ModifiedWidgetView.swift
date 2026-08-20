import OpenWidgetRuntime

nonisolated struct ModifiedWidgetView<Content>: View where Content: View {
    typealias Body = Never

    let content: Content
    let modifier: WidgetModifier
}

extension ModifiedWidgetView: WidgetNodeConvertible {
    @MainActor
    package func makeWidgetNodes(
        in context: inout WidgetViewGraphContext
    ) throws -> [WidgetNode] {
        try validate(modifier)
        let id = context.path
        let children = try context.withPath(.role("content")) {
            try lowerWidgetView(content, in: &$0)
        }
        return [WidgetNode(id: id, kind: .modified(modifier), children: children)]
    }

    private func validate(_ modifier: WidgetModifier) throws {
        switch modifier {
        case .padding(_, let insets):
            guard let insets else { return }
            try validateFinite(insets.top, field: "padding.top")
            try validateFinite(insets.leading, field: "padding.leading")
            try validateFinite(insets.bottom, field: "padding.bottom")
            try validateFinite(insets.trailing, field: "padding.trailing")
        case .frame(let frame):
            try validateFrame(frame)
        case .lineLimit(let limit):
            if let limit, limit < 0 {
                throw WidgetSemanticError.invalidLineLimit(limit)
            }
        case .font, .foregroundColor:
            return
        }
    }

    private func validateFrame(_ frame: WidgetFrame) throws {
        let values: [(String, CGFloat?)] = [
            ("frame.minWidth", frame.minWidth),
            ("frame.idealWidth", frame.idealWidth),
            ("frame.maxWidth", frame.maxWidth),
            ("frame.minHeight", frame.minHeight),
            ("frame.idealHeight", frame.idealHeight),
            ("frame.maxHeight", frame.maxHeight)
        ]
        for (field, value) in values {
            if let value {
                try validateFinite(value, field: field)
            }
        }

        guard Self.isNondecreasing(
            minimum: frame.minWidth,
            ideal: frame.idealWidth,
            maximum: frame.maxWidth
        ) else {
            throw WidgetSemanticError.invalidFrameRange(axis: "horizontal")
        }
        guard Self.isNondecreasing(
            minimum: frame.minHeight,
            ideal: frame.idealHeight,
            maximum: frame.maxHeight
        ) else {
            throw WidgetSemanticError.invalidFrameRange(axis: "vertical")
        }
    }

    private func validateFinite(_ value: CGFloat, field: String) throws {
        guard value.isFinite else {
            throw WidgetSemanticError.nonFiniteLayoutValue(field: field)
        }
    }

    private static func isNondecreasing(
        minimum: CGFloat?,
        ideal: CGFloat?,
        maximum: CGFloat?
    ) -> Bool {
        let lower = minimum ?? -.infinity
        let middle = ideal ?? lower
        let upper = maximum ?? middle
        return lower <= middle && middle <= upper
    }
}
