import SwiftUI

struct ConversationsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversations")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("New") {
                    appState.startNewConversation()
                    dismiss()
                }
                .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            if appState.conversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .frame(width: 400, height: 480)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("No conversations yet")
                .foregroundColor(.secondary)
            Button("Start one") {
                appState.startNewConversation()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    // MARK: - List

    @State private var hoveredId: UUID?
    @State private var confirmDeleteId: UUID?

    private var conversationList: some View {
        List {
            ForEach(appState.conversations) { conv in
                row(conv)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .onDelete { idx in
                idx.forEach { appState.deleteConversation(appState.conversations[$0]) }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ conv: Conversation) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conv.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(conv.messages.filter { $0.role == .user || $0.role == .assistant }.count) messages")
                    Text("·")
                    Text(conv.updatedAt, style: .relative) + Text(" ago")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            if appState.currentConversation?.id == conv.id {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }

            // Delete button — visible on hover or while confirm dialog is open
            if hoveredId == conv.id || confirmDeleteId == conv.id {
                Button {
                    confirmDeleteId = conv.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete conversation")
            }
        }
        .contentShape(Rectangle())
        // Dialog lives on the row itself — not on the button — so it survives hover changes
        .confirmationDialog(
            "Delete \"\(conv.title)\"?",
            isPresented: Binding(
                get: { confirmDeleteId == conv.id },
                set: { if !$0 { confirmDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.deleteConversation(conv)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onHover { hovered in
            hoveredId = hovered ? conv.id : nil
        }
        .onTapGesture {
            appState.selectConversation(conv)
            dismiss()
        }
    }
}
