import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    let conversation: Conversation

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
                    // role==.tool messages are hidden (they're only for API context)
                    ForEach(conversation.messages.filter { $0.isVisible }) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    // Invisible anchor for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 10)
            }
            .onChange(of: conversation.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Scroll while streaming (content token-by-token)
            .onChange(of: conversation.messages.last?.content) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}
