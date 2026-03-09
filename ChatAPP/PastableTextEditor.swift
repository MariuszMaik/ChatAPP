import AppKit
import SwiftUI

/// NSTextView wrapper that:
/// - Sends on Return, inserts newline on Shift+Return
/// - Intercepts Cmd+V paste to detect pasted images and files
struct PastableTextEditor: NSViewRepresentable {

    @Binding var text: String
    var onSend: () -> Void
    var onImagePaste: (Data) -> Void
    var onFilePaste: ((URL) -> Void)? = nil
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
        tv.onFilePaste  = onFilePaste
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

        // Focus the text view whenever our window becomes key
        context.coordinator.windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak tv] notification in
            guard let tv = tv,
                  let keyWindow = notification.object as? NSWindow,
                  tv.window === keyWindow else { return }
            keyWindow.makeFirstResponder(tv)
        }

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
            tv.onFilePaste  = onFilePaste
        }
    }

    // MARK: Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PastableTextEditor
        var windowObserver: Any?

        init(_ parent: PastableTextEditor) { self.parent = parent }

        deinit {
            if let obs = windowObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

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
    var onFilePaste:  ((URL) -> Void)?

    // Return → send; Shift+Return → newline
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 /* Return */ && !event.modifierFlags.contains(.shift) {
            onSend?()
        } else {
            super.keyDown(with: event)
        }
    }

    // Intercept paste to detect files and images
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        // Raw image data (screenshots, images from browser/apps).
        // Using pb.data(forType:) reads inline bytes and avoids sandbox file-URL issues.
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.apple.pict")
        ]
        for type in imageTypes {
            if let data = pb.data(forType: type),
               let img  = NSImage(data: data),
               let png  = img.pngData() {
                onImagePaste?(png)
                return
            }
        }

        // Files copied in Finder (PDFs, text files, image files, etc.)
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            urls.forEach { onFilePaste?($0) }
            return
        }

        super.paste(sender)
    }
}
