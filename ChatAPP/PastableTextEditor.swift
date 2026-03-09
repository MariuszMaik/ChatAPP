import AppKit
import SwiftUI

/// NSTextView wrapper that:
/// - Sends on Return, inserts newline on Shift+Return
/// - Intercepts Cmd+V paste to detect pasted images
struct PastableTextEditor: NSViewRepresentable {

    @Binding var text: String
    var onSend: () -> Void
    var onImagePaste: (Data) -> Void
    var placeholder: String = "Message…  (⏎ send · ⇧⏎ newline)"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tv = InternalTextView()
        tv.onSend       = onSend
        tv.onImagePaste = onImagePaste
        tv.delegate     = context.coordinator
        tv.isRichText   = false
        tv.isEditable   = true
        tv.font         = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.drawsBackground = false
        tv.autoresizingMask = [.width]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled  = false

        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel
        }
        if let tv = tv as? InternalTextView {
            tv.onSend       = onSend
            tv.onImagePaste = onImagePaste
        }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PastableTextEditor
        init(_ parent: PastableTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - Internal NSTextView

private final class InternalTextView: NSTextView {
    var onSend:       (() -> Void)?
    var onImagePaste: ((Data) -> Void)?

    // Return → send; Shift+Return → newline
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 /* Return */ && !event.modifierFlags.contains(.shift) {
            onSend?()
        } else {
            super.keyDown(with: event)
        }
    }

    // Intercept paste to detect images
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) {
            onImagePaste?(data); return
        }
        if let data = pb.data(forType: .tiff),
           let img = NSImage(data: data),
           let png = img.pngData() {
            onImagePaste?(png); return
        }
        super.paste(sender)
    }
}
