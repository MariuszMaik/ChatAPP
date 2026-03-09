import AppKit
import SwiftUI

struct MessageBubble: View {
    let message: Message
    @State private var copied = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        // Tool-call chip row (assistant requested tools)
        if message.role == .assistant, let calls = message.toolCalls, !calls.isEmpty {
            toolCallChips(calls)
        }
        // Regular user/assistant bubble
        else if message.isVisible {
            HStack(alignment: .top, spacing: 8) {
                if isUser { Spacer(minLength: 48) }

                VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                    if !message.attachments.isEmpty { attachmentsRow }
                    if !message.content.isEmpty || message.isStreaming { bubble }
                }

                if !isUser { Spacer(minLength: 48) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
        // Tool result messages are intentionally invisible (role == .tool)
    }

    // MARK: - Tool call chips

    private func toolCallChips(_ calls: [ToolCall]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(calls) { tc in
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(tc.name)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    // Show first arg value if available
                    if let firstVal = firstArgValue(tc.arguments) {
                        Text("(\(firstVal))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }

    private func firstArgValue(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = dict.values.first
        else { return nil }
        let s = "\(first)"
        return s.count > 40 ? String(s.prefix(40)) + "…" : s
    }

    // MARK: - Attachment thumbnails

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(message.attachments) { att in attachmentChip(att) }
            }
        }
    }

    @ViewBuilder
    private func attachmentChip(_ att: Attachment) -> some View {
        if att.type == .image, let data = att.data, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().scaledToFill()
                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Label(att.displayName, systemImage: att.icon)
                .font(.caption).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Text bubble

    private var bubble: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Group {
                if isUser {
                    // Plain text for user messages
                    Text(message.content + (message.isStreaming ? "▋" : ""))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    // Markdown for assistant messages
                    VStack(alignment: .leading, spacing: 0) {
                        if message.isStreaming && message.content.isEmpty {
                            // Spinner while waiting for first token
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Thinking…").foregroundColor(.secondary).font(.caption)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        } else {
                            MarkdownView(text: message.content + (message.isStreaming ? "▋" : ""))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            // Copy button for assistant messages
            if !isUser && !message.isStreaming && !message.content.isEmpty {
                copyButton
            }
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            Label(copied ? "Copied" : "Copy",
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.caption2).foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
