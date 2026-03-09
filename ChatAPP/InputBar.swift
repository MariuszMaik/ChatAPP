import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InputBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var folder = FolderAccessManager.shared

    @State private var text: String = ""
    @State private var attachments: [Attachment] = []
    @State private var isDragging = false

    private var canSend: Bool {
        !appState.isStreaming &&
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Folder badge
            if folder.isAttached {
                folderBadge
                Divider()
            }

            // Pending file attachments
            if !attachments.isEmpty {
                pendingAttachmentsBar
                Divider()
            }

            // Text editor — full width
            PastableTextEditor(
                text: $text,
                onSend: send,
                onImagePaste: { data in
                    if let att = FileService.shared.processImageData(data) {
                        attachments.append(att)
                    }
                },
                onFilePaste: { url in
                    if let att = FileService.shared.processFile(url: url) {
                        attachments.append(att)
                    }
                }
            )
            .frame(minHeight: 36, maxHeight: 120)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Toolbar row below the editor
            HStack(spacing: 4) {
                // Attach file
                Button { pickFiles() } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Attach file  (image, text, PDF)")

                // Attach/detach folder
                Button { toggleFolder() } label: {
                    Image(systemName: folder.isAttached ? "folder.badge.minus" : "folder.badge.plus")
                        .font(.system(size: 16))
                        .foregroundColor(folder.isAttached ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(folder.isAttached ? "Detach folder" : "Attach project folder (enables tool access)")

                Spacer()

                // Send
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(canSend ? .accentColor : Color(NSColor.disabledControlTextColor))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier],
                isTargeted: $isDragging, perform: handleDrop)
        .overlay(
            isDragging ? RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2).padding(4) : nil
        )
        .onReceive(NotificationCenter.default.publisher(for: .chatAppPasteImage)) { note in
            if let data = note.userInfo?["data"] as? Data,
               let att  = FileService.shared.processImageData(data) {
                attachments.append(att)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatAppPasteFiles)) { note in
            if let urls = note.userInfo?["urls"] as? [URL] {
                attachments.append(contentsOf: urls.compactMap { FileService.shared.processFile(url: $0) })
            }
        }
    }

    // MARK: - Folder badge

    private var folderBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundColor(.accentColor)
            Text(folder.displayName)
                .font(.caption)
                .lineLimit(1)
            Text("· tool access enabled")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button {
                folder.detachFolder()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.07))
    }

    // MARK: - Pending attachments strip

    private var pendingAttachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { att in chip(att) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func chip(_ att: Attachment) -> some View {
        HStack(spacing: 4) {
            if att.type == .image, let data = att.data, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: att.icon).foregroundColor(.accentColor)
                Text(att.displayName).font(.caption).lineLimit(1)
            }
            Button { attachments.removeAll { $0.id == att.id } } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func send() {
        guard canSend else { return }
        let msg  = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let atts = attachments
        text = ""; attachments = []
        appState.sendMessage(msg, attachments: atts)
    }

    private func pickFiles() {
        attachments.append(contentsOf: FileService.shared.pickFiles())
    }

    private func toggleFolder() {
        if folder.isAttached {
            folder.detachFolder()
        } else {
            folder.attachFolder()
        }
    }

    // MARK: - Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url  = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if let att = FileService.shared.processFile(url: url) { self.attachments.append(att) }
                    }
                }
                handled = true
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                p.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage, let png = img.pngData() else { return }
                    DispatchQueue.main.async {
                        if let att = FileService.shared.processImageData(png, name: "Dropped Image") {
                            self.attachments.append(att)
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}
