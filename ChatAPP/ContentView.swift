import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings      = false
    @State private var showConversations = false

    var body: some View {
        Group {
            if !appState.isSetupComplete {
                SetupView()
                    .environmentObject(appState)
            } else {
                mainView
            }
        }
        .frame(minWidth: 340, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Main chat layout

    private var mainView: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let conv = appState.currentConversation {
                ChatView(conversation: conv)
                    .environmentObject(appState)
            } else {
                placeholder
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(appState)
        }
        .sheet(isPresented: $showConversations) {
            ConversationsView().environmentObject(appState)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            // New conversation
            toolbarButton(icon: "square.and.pencil", help: "New conversation") {
                appState.startNewConversation()
            }

            Spacer()

            Text(appState.currentConversation?.title ?? "ChatAPP")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200)

            Spacer()

            // Conversations history
            toolbarButton(icon: "clock.arrow.circlepath", help: "History") {
                showConversations = true
            }

            // Settings
            toolbarButton(icon: "gear", help: "Settings") {
                showSettings = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func toolbarButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Empty placeholder

    private var placeholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No conversation open")
                .foregroundColor(.secondary)
            Button("New Conversation") { appState.startNewConversation() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
