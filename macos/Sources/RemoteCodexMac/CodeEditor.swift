import AppKit
import SwiftUI
import RemoteCodexCore

/// Native text editing with temporary layout colors: highlighting never changes
/// file bytes, selection, marked text or the text view's undo history.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    let path: String
    let fontSize: CGFloat
    let onSave: () -> Void
    @Environment(\.colorScheme) var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = EditorTextView(frame: .zero)
        view.isRichText = false; view.allowsUndo = true; view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityIdentifier("fileEditor"); view.setAccessibilityLabel("File contents")
        view.delegate = context.coordinator; view.onSave = onSave
        scroll.documentView = view
        context.coordinator.view = view
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.parent = self
        guard let view = coordinator.view else { return }
        view.onSave = onSave
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if view.font != font { view.font = font }
        let base = colorScheme == .dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.12, alpha: 1)
        view.textColor = base; view.insertionPointColor = base
        if view.string != text, !view.hasMarkedText() {
            let selection = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            view.undoManager?.removeAllActions()
        }
        coordinator.highlight()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.task?.cancel(); coordinator.view?.delegate = nil
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var view: EditorTextView?
        var task: Task<Void, Never>?
        private var lastText: String?
        private var lastPath = ""
        private var lastDark = false
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view else { return }
            parent.text = view.string
            highlight()
        }
        func highlight() {
            guard let view, !view.hasMarkedText() else { return }
            let text = view.string, path = parent.path, dark = parent.colorScheme == .dark
            guard text != lastText || path != lastPath || dark != lastDark else { return }
            lastText = text; lastPath = path; lastDark = dark; task?.cancel()
            task = Task { @MainActor [weak self, weak view] in
                do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
                let tokens = await Task.detached(priority: .userInitiated) { CodeSyntax.tokens(text, path: path) }.value
                guard !Task.isCancelled, let self, let view, view.string == text, !view.hasMarkedText(), let layout = view.layoutManager else { return }
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: (text as NSString).length))
                for token in tokens { layout.addTemporaryAttribute(.foregroundColor, value: self.color(token.kind, dark: dark), forCharacterRange: token.range) }
            }
        }
        private func color(_ kind: CodeSyntax.Kind, dark: Bool) -> NSColor {
            let rgb: UInt32
            switch kind {
            case .comment: rgb = dark ? 0x8B9D88 : 0x54724D
            case .string: rgb = dark ? 0xE8B998 : 0x9C3D18
            case .number: rgb = dark ? 0xA8D5B1 : 0x126E55
            case .keyword: rgb = dark ? 0xCDA5E8 : 0x8238A4
            case .type: rgb = dark ? 0x71D2C1 : 0x08756C
            case .function: rgb = dark ? 0xE4DB9D : 0x765D08
            }
            return NSColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}

final class EditorTextView: NSTextView {
    var onSave: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "s" { onSave?(); return true }
        return super.performKeyEquivalent(with: event)
    }
}
