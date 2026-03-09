import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            Divider()
            InputBar()
                .environmentObject(appState)
        }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(conversation.messages.filter { $0.isVisible }) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    // Invisible anchor — onAppear/onDisappear tracks whether user is at bottom
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear   { isAtBottom = true  }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.vertical, 10)
            }
            // Jump-to-bottom button, shown when user has scrolled up
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                }
            }
            // New message added → always scroll to bottom
            .onChange(of: conversation.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Streaming token → only scroll if already at bottom
            .onChange(of: conversation.messages.last?.content) { _ in
                guard isAtBottom else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
