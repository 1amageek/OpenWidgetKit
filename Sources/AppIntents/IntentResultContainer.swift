@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentResultContainer<
    _Value,
    _OpensAppIntent,
    _Snippet,
    _Dialog
>:
    IntentResult,
    Sendable
{
    public typealias Value = _Value
    public typealias OpensAppIntent = _OpensAppIntent
    public typealias Snippet = _Snippet
    public typealias Dialog = _Dialog

    public var value: _Value? { nil }

    package init() {}
}

extension IntentResultContainer: WidgetExecutableIntentResult
where
    _Value == Never,
    _OpensAppIntent == Never,
    _Snippet == Never,
    _Dialog == Never
{}
