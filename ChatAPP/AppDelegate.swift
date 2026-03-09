import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let appState = AppState()
    private var statusItem: NSStatusItem!
    private var chatWindow: ChatWindow!
    private var hotkeyManager: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupWindow()
        appState.loadData()
        setupHotkey()           // after loadData so saved hotkey is available
        observeHotkeyChanges()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill",
                                accessibilityDescription: "ChatAPP")
            btn.action = #selector(handleStatusClick)
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            btn.target = self
        }
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleWindow()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: chatWindow.isVisible ? "Hide ChatAPP" : "Show ChatAPP",
                     action: #selector(toggleWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ChatAPP",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        // Temporarily attach menu so it pops up at the icon, then remove it
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Window

    private func setupWindow() {
        let root = ContentView().environmentObject(appState)
        chatWindow = ChatWindow(rootView: AnyView(root))
        chatWindow.delegate = self
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        let s = appState.settings
        hotkeyManager = HotkeyManager(
            keyCode:   s.hotkeyKeyCode,
            modifiers: s.hotkeyModifiers
        ) { [weak self] in
            DispatchQueue.main.async { self?.toggleWindow() }
        }
    }

    private func observeHotkeyChanges() {
        // Break the chain into typed steps to help the compiler
        let keyPairs = appState.$settings
            .dropFirst()
            .map { s -> (UInt32, UInt32) in (s.hotkeyKeyCode, s.hotkeyModifiers) }
        keyPairs
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pair in
                self?.hotkeyManager?.update(keyCode: pair.0, modifiers: pair.1)
            }
            .store(in: &cancellables)
    }

    // MARK: - Toggle

    @objc func toggleWindow() {
        if chatWindow.isVisible && NSApp.isActive {
            chatWindow.orderOut(nil)
        } else {
            chatWindow.positionBottomRight()
            chatWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

// MARK: - Custom window

final class ChatWindow: NSWindow {

    init(rootView: AnyView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
            styleMask:   [.titled, .closable, .resizable, .fullSizeContentView],
            backing:     .buffered,
            defer:       false
        )
        title = "ChatAPP"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .windowBackgroundColor
        minSize = NSSize(width: 340, height: 480)
        contentViewController = NSHostingController(rootView: rootView)
    }

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }

    func positionBottomRight() {
        guard let screen = NSScreen.main else { return }
        let sf     = screen.visibleFrame
        let wf     = frame
        let margin: CGFloat = 16
        setFrameOrigin(NSPoint(
            x: sf.maxX - wf.width  - margin,
            y: sf.minY + margin
        ))
    }
}
