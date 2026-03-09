import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var settings: AppSettings = AppSettings()
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var availableModels: [String] = []
    @Published var isLoadingModels: Bool = false
    @Published var setupError: String?
    @Published var isStreaming: Bool = false

    var isSetupComplete: Bool { settings.isConfigured }

    // MARK: - Services

    private let storage = StorageService.shared
    private let openAI  = OpenAIService.shared
    private let folder  = FolderAccessManager.shared

    // MARK: - Persistence

    func loadData() {
        settings            = storage.loadSettings()
        settings.apiKey     = storage.loadAPIKey()
        conversations       = storage.loadConversations()
        availableModels     = settings.availableModels
        currentConversation = conversations.first
        folder.restoreFromBookmark()
    }

    func saveData() {
        storage.saveAPIKey(settings.apiKey)
        storage.saveSettings(settings)
        storage.saveConversations(conversations)
    }

    // MARK: - Setup

    func fetchModels() async {
        isLoadingModels = true
        setupError = nil
        do {
            let models = try await openAI.fetchModels(
                endpoint: settings.apiEndpoint,
                apiKey: settings.apiKey
            )
            availableModels = models
            settings.availableModels = models
            if settings.selectedModel.isEmpty { settings.selectedModel = models.first ?? "" }
        } catch {
            setupError = error.localizedDescription
        }
        isLoadingModels = false
    }

    func completeSetup() { saveData() }

    // MARK: - Conversations

    func startNewConversation() {
        let conv = Conversation(title: "New Conversation")
        conversations.insert(conv, at: 0)
        currentConversation = conv
        saveData()
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        saveData()
    }

    // MARK: - Messaging entry point

    func sendMessage(_ content: String, attachments: [Attachment]) {
        guard !isStreaming else { return }
        if currentConversation == nil { startNewConversation() }
        guard var conv = currentConversation else { return }

        // Append user message
        let userMsg = Message(role: .user, content: content, attachments: attachments)
        conv.messages.append(userMsg)
        conv.updatedAt = Date()
        if conv.messages.count == 1 {
            conv.title = Conversation.generateTitle(from: conv.messages)
        }
        updateCurrent(conv)
        isStreaming = true

        if folder.isAttached {
            Task { await runToolCallingLoop() }
        } else {
            Task { await runStreamingReply() }
        }
    }

    // MARK: - Streaming reply (no tools)

    private func runStreamingReply() async {
        guard var conv = currentConversation else { isStreaming = false; return }

        let assistantMsg = Message(role: .assistant, content: "", isStreaming: true)
        let aid = assistantMsg.id
        conv.messages.append(assistantMsg)
        updateCurrent(conv)

        let messagesToSend = conv.messages.filter { !$0.isStreaming }
        let snap = settings

        do {
            try await openAI.streamChat(
                messages: messagesToSend,
                settings: snap,
                onToken: { [weak self] token in
                    Task { @MainActor [weak self] in self?.appendToken(token, id: aid) }
                }
            )
        } catch {
            replaceMessage(id: aid, with: "Error: \(error.localizedDescription)")
        }
        finishStreaming(id: aid)
    }

    // MARK: - Tool-calling loop (non-streaming rounds → final content)

    private func runToolCallingLoop() async {
        guard var conv = currentConversation else { isStreaming = false; return }

        // Build initial API messages with optional system prompt
        var apiMessages = await openAI.buildAPIMessages(from: conv.messages)
        let sysPrompt = folder.systemPrompt
        if !sysPrompt.isEmpty {
            apiMessages.insert(["role": "system", "content": sysPrompt], at: 0)
        }
        let tools = folder.toolDefinitions
        let snap  = settings

        // Tool-calling loop
        var loopCount = 0
        let maxLoops  = 10

        while loopCount < maxLoops {
            loopCount += 1
            let completion: ChatCompletion
            do {
                completion = try await openAI.sendChatCompletion(
                    apiMessages: apiMessages,
                    settings: snap,
                    tools: tools
                )
            } catch {
                appendErrorMessage("API error: \(error.localizedDescription)")
                isStreaming = false
                return
            }

            let finishReason = completion.finishReason ?? "stop"

            if finishReason == "tool_calls",
               let toolCalls = completion.apiToolCalls, !toolCalls.isEmpty {

                // 1. Add assistant tool-call message to conversation (visible as chips)
                let tcMessage = Message(
                    role: .assistant,
                    content: "",
                    toolCalls: toolCalls.map { ToolCall(id: $0.id, name: $0.function.name, arguments: $0.function.arguments) }
                )
                conv.messages.append(tcMessage)
                updateCurrent(conv)

                // 2. Add assistant tool-call to API messages
                apiMessages.append([
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": toolCalls.map { tc -> [String: Any] in
                        ["id": tc.id, "type": "function",
                         "function": ["name": tc.function.name, "arguments": tc.function.arguments]]
                    }
                ])

                // 3. Execute each tool and add results
                for tc in toolCalls {
                    let result = folder.executeTool(name: tc.function.name, arguments: tc.function.arguments)

                    // Hidden tool result message (for API context)
                    let toolMsg = Message(
                        role: .tool,
                        content: result,
                        toolCallId: tc.id
                    )
                    conv.messages.append(toolMsg)
                    updateCurrent(conv)

                    // Add to API messages
                    apiMessages.append([
                        "role": "tool",
                        "tool_call_id": tc.id,
                        "content": result
                    ])
                }

            } else {
                // Final response — show it
                let finalText = completion.content ?? ""
                let finalMsg  = Message(role: .assistant, content: finalText)
                conv.messages.append(finalMsg)
                conv.updatedAt = Date()
                updateCurrent(conv)
                saveData()
                isStreaming = false
                return
            }
        }

        // Max loops hit
        appendErrorMessage("Tool loop limit reached (\(maxLoops) iterations).")
        isStreaming = false
    }

    // MARK: - Helpers

    private func appendToken(_ token: String, id: UUID) {
        guard var conv = currentConversation,
              let idx  = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].content += token
        updateCurrent(conv)
    }

    private func finishStreaming(id: UUID) {
        guard var conv = currentConversation,
              let idx  = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].isStreaming = false
        conv.updatedAt = Date()
        updateCurrent(conv)
        isStreaming = false
        saveData()
    }

    private func replaceMessage(id: UUID, with text: String) {
        guard var conv = currentConversation,
              let idx  = conv.messages.firstIndex(where: { $0.id == id }) else { return }
        conv.messages[idx].content    = text
        conv.messages[idx].isStreaming = false
        updateCurrent(conv)
    }

    private func appendErrorMessage(_ text: String) {
        guard var conv = currentConversation else { return }
        conv.messages.append(Message(role: .assistant, content: text))
        updateCurrent(conv)
    }

    private func updateCurrent(_ conv: Conversation) {
        currentConversation = conv
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[idx] = conv
        }
    }
}
