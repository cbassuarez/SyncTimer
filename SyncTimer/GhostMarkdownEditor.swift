import SwiftUI

/// GhostMarkdownEditor:
/// - Background layer: live Markdown render (SwiftUI Text/AttributedString)
/// - Foreground layer: TextEditor with transparent text to keep caret & typing UX
/// - 10k hard cap, zero flicker, no TextKit resets
struct GhostMarkdownEditor: View {
    @Binding var text: String
    var isEditable: Bool
    var characterLimit: Int = 10_000
    // Typography
    private let bodyFont = Font.custom("Roboto-Regular", size: 16)

    // Live Markdown render
    private var rendered: AttributedString {
        if text.isEmpty { return AttributedString("") }
        if let asg = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return asg
        }
        return AttributedString(text)   // fallback
    }

    @State private var internalText: String = ""

    var body: some View {
        // Keep internal buffer synced but enforce hard cap pre-insert
        ZStack(alignment: .topLeading) {
            // Render layer
            ScrollView(.vertical) {
                Text(rendered)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
            }
            .scrollDisabled(true) // Scrolling handled by editor

            // Editor layer (transparent glyphs; caret remains via .tint)
            TextEditor(text: $internalText)
                .font(bodyFont)
                .foregroundColor(.clear)        // hide glyphs
                .tint(.accentColor)             // keep caret visible
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.vertical, 6)          // align with render padding
                .padding(.horizontal, 2)
                .disabled(!isEditable)
                .opacity(isEditable ? 1 : 0.999) // keep layout stable even when disabled
                .onChange(of: internalText) { newVal in
                    // Hard 10k cap
                    if newVal.count > characterLimit {
                        internalText = String(newVal.prefix(characterLimit))
                    }
                    // write-through
                    if text != internalText { text = internalText }
                }
                .onChange(of: text) { newVal in
                    // Pull external changes (AppStorage or sync) without loops
                    if internalText != newVal {
                        internalText = String(newVal.prefix(characterLimit))
                    }
                }
                .onAppear {
                    internalText = String(text.prefix(characterLimit))
                }
        }
        // Ensure the editor consumes taps for focus first
        .contentShape(Rectangle())
    }
}
