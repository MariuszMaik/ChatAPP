import SwiftUI

@main
struct ChatAPPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No regular windows — the app lives in the menu bar.
        Settings { EmptyView() }
    }
}
