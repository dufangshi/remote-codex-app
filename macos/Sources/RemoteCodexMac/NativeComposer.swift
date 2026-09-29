import SwiftUI

/// SwiftUI owns the editable surface, selection, undo and accessibility.
struct NativeComposer: View {
    var textSize = TextSizePreference()
    @Binding var text: String
    var code = false
    var readOnly = false
    var identifier = "messageInput"
    let onSubmit: () -> Void
    var body: some View {
        Group {
            if readOnly {
                ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                TextEditor(text: $text).scrollContentBackground(.hidden)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) { onSubmit(); return .handled }
                        return .ignored
                    }
            }
        }.font(code ? .system(size: textSize.points(13), design: .monospaced) : .system(size: textSize.points(15)))
            .foregroundStyle(Palette.text).scrollIndicators(.never)
            .accessibilityIdentifier(identifier).accessibilityLabel(code ? "File contents" : "Message your agent")
    }
}
