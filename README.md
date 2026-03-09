# ChatAPP

macOS menu bar chat app with OpenAI-compatible API support.

## Features

- Menu bar icon + global hotkey (⌃⌥Space) to toggle
- Streaming responses with Markdown & syntax highlighting
- Attach images, PDFs, and text files
- Secure folder access via OpenAI tool calling
- Conversation history
- API key stored in Keychain, chat history AES-256-GCM encrypted

## Download

Download the latest `ChatAPP-v1.1.zip` from [Releases](https://github.com/MariuszMaik/ChatAPP/releases), unzip, and run. Since the app is not notarized, macOS will block it on first launch. To fix, run once in Terminal:

```bash
xattr -dr com.apple.quarantine ChatAPP.app
```

## Build

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
mkdir -p ChatAPP/build
xcrun swiftc \
  -sdk $(xcrun --show-sdk-path) \
  -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -framework CryptoKit -framework Carbon -framework Combine \
  -framework UniformTypeIdentifiers \
  ChatAPP/*.swift -o ChatAPP/build/ChatAPP
```

Then wrap in an `.app` bundle or open the `.xcodeproj` in Xcode.
