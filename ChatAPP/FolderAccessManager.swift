import Foundation
import AppKit

// MARK: - Errors

enum FolderError: LocalizedError {
    case noFolderAttached
    case accessDenied
    case pathTraversal
    case pathEscape(String)
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .noFolderAttached:       return "No folder attached."
        case .accessDenied:           return "Access denied to the selected folder."
        case .pathTraversal:          return "Path contains '..' — traversal not allowed."
        case .pathEscape(let p):      return "Path '\(p)' would escape the project folder."
        case .fileTooLarge(let sz):   return "File is \(sz / 1000)KB — too large to read."
        }
    }
}

// MARK: - Manager

final class FolderAccessManager: ObservableObject {
    static let shared = FolderAccessManager()
    private init() {}

    @Published private(set) var rootURL: URL?
    private var resolvedRootPath: String = ""
    private let bookmarkKey = "com.chatapp.folderBookmark"
    private let maxFileBytes = 50_000

    var isAttached: Bool { rootURL != nil }
    var displayName: String { rootURL?.lastPathComponent ?? "" }

    // MARK: - Attach / Detach

    @MainActor
    func attachFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories  = true
        panel.canChooseFiles        = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder to give ChatAPP access"
        panel.prompt  = "Attach"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try setRoot(url: url) }
        catch { print("Folder attach error: \(error)") }
    }

    func detachFolder() {
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL          = nil
        resolvedRootPath = ""
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        objectWillChange.send()
    }

    func restoreFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale),
           url.startAccessingSecurityScopedResource() {
            rootURL          = url
            resolvedRootPath = realpath(url.path)
        }
    }

    private func setRoot(url: URL) throws {
        rootURL?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { throw FolderError.accessDenied }
        if let bm = try? url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil) {
            UserDefaults.standard.set(bm, forKey: bookmarkKey)
        }
        rootURL          = url
        resolvedRootPath = realpath(url.path)
        objectWillChange.send()
    }

    // MARK: - Path security

    /// Returns a validated, real URL for a path relative to the attached root.
    func validated(relativePath: String) throws -> URL {
        guard let root = rootURL else { throw FolderError.noFolderAttached }

        // Reject explicit ".." components
        let components = relativePath.components(separatedBy: "/")
        if components.contains("..") { throw FolderError.pathTraversal }

        // Build the candidate absolute path and resolve symlinks
        let candidate = root
            .appendingPathComponent(relativePath)
            .standardized
        let resolved  = realpath(candidate.path)

        // Must start with root
        let prefix = resolvedRootPath.hasSuffix("/") ? resolvedRootPath : resolvedRootPath + "/"
        guard resolved == resolvedRootPath || resolved.hasPrefix(prefix) else {
            throw FolderError.pathEscape(relativePath)
        }
        return URL(fileURLWithPath: resolved)
    }

    private func realpath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return Darwin.realpath(path, &buf).map { String(cString: $0) } ?? path
    }

    // MARK: - Tool: list_directory

    func listDirectory(path: String) throws -> String {
        let url   = try validated(relativePath: path)
        let items = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        if items.isEmpty { return "(empty directory)" }
        return items.map { item in
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size  = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return isDir ? "📁 \(item.lastPathComponent)/" : "📄 \(item.lastPathComponent)  (\(formatSize(size)))"
        }.joined(separator: "\n")
    }

    // MARK: - Tool: read_file

    func readFile(path: String) throws -> String {
        let url  = try validated(relativePath: path)
        let data = try Data(contentsOf: url)
        let text = String(data: data.prefix(maxFileBytes), encoding: .utf8)
            ?? String(data: data.prefix(maxFileBytes), encoding: .isoLatin1)
            ?? "<binary file — cannot display>"
        if data.count > maxFileBytes {
            return text + "\n\n…[truncated at 50 KB; full file is \(formatSize(data.count))]"
        }
        return text
    }

    // MARK: - Tool: read_file_lines

    func readFileLines(path: String, start: Int, end: Int) throws -> String {
        let content = try readFile(path: path)
        let lines   = content.components(separatedBy: "\n")
        let s = max(1, start) - 1
        let e = min(end, lines.count) - 1
        guard s <= e, s < lines.count else { return "(no lines in that range)" }
        return lines[s...e].enumerated()
            .map { "\(s + $0.offset + 1): \($0.element)" }
            .joined(separator: "\n")
    }

    // MARK: - Tool: search_code

    func searchCode(query: String, fileExtension: String? = nil) throws -> String {
        guard let root = rootURL else { throw FolderError.noFolderAttached }

        let codeExts = Set(["swift","py","js","ts","jsx","tsx","java","kt","go","rs",
                            "cpp","c","h","m","mm","rb","php","cs","html","css",
                            "json","yaml","yml","toml","md","txt","sh","bash","zsh","sql"])
        let targetExts: Set<String>
        if let ext = fileExtension?.lowercased(), !ext.isEmpty {
            targetExts = [ext]
        } else {
            targetExts = codeExts
        }

        var results: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard results.count < 50 else { break }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  targetExts.contains(fileURL.pathExtension.lowercased())
            else { continue }

            let rel = String(fileURL.path.dropFirst(root.path.count + 1))
            guard let validURL = try? validated(relativePath: rel),
                  let text = try? String(contentsOf: validURL, encoding: .utf8)
            else { continue }

            let lines = text.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(query) {
                    results.append("\(rel):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    if results.count >= 50 { break }
                }
            }
        }
        return results.isEmpty
            ? "No matches found for '\(query)'"
            : results.joined(separator: "\n")
    }

    // MARK: - Tool dispatch

    func executeTool(name: String, arguments: String) -> String {
        guard let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] else {
            return "Error: could not parse tool arguments as JSON."
        }
        do {
            switch name {
            case "list_directory":
                return try listDirectory(path: args["path"] as? String ?? ".")
            case "read_file":
                return try readFile(path: args["path"] as? String ?? "")
            case "read_file_lines":
                return try readFileLines(
                    path:  args["path"]  as? String ?? "",
                    start: args["start"] as? Int    ?? 1,
                    end:   args["end"]   as? Int    ?? 50
                )
            case "search_code":
                return try searchCode(
                    query:         args["query"]          as? String ?? "",
                    fileExtension: args["file_extension"] as? String
                )
            default:
                return "Unknown tool: \(name)"
            }
        } catch {
            return "Tool error: \(error.localizedDescription)"
        }
    }

    // MARK: - OpenAI tool definitions

    var toolDefinitions: [[String: Any]] {
        guard isAttached else { return [] }
        return [
            tool("list_directory",
                 desc: "List files and subdirectories at the given path relative to the project root.",
                 params: ["path": param("string", "Path relative to project root. Use '.' for the root.")],
                 required: ["path"]),
            tool("read_file",
                 desc: "Read a file's content (max 50 KB). Use for source code, configs, docs.",
                 params: ["path": param("string", "Path relative to project root.")],
                 required: ["path"]),
            tool("read_file_lines",
                 desc: "Read specific lines of a file.",
                 params: [
                    "path":  param("string",  "Path relative to project root."),
                    "start": param("integer", "First line number (1-indexed, inclusive)."),
                    "end":   param("integer", "Last line number (inclusive).")
                 ],
                 required: ["path", "start", "end"]),
            tool("search_code",
                 desc: "Search for a text/pattern in all code files in the project.",
                 params: [
                    "query":          param("string", "Text to search for (case-insensitive)."),
                    "file_extension": param("string", "Optional: limit to files with this extension, e.g. 'swift'.")
                 ],
                 required: ["query"])
        ]
    }

    /// System prompt injected when folder is attached.
    var systemPrompt: String {
        guard let name = rootURL?.lastPathComponent else { return "" }
        return """
        You have read-only access to the project folder '\(name)' via these tools:
        • list_directory(path) — list files/dirs at a path relative to the root
        • read_file(path) — read file contents (max 50 KB)
        • read_file_lines(path, start, end) — read specific line range
        • search_code(query[, file_extension]) — full-text search across code files

        Use the tools to explore the project before answering questions about it.
        Paths are always relative to the project root. Start with list_directory('.').
        """
    }

    // MARK: - Helpers

    private func tool(_ name: String, desc: String, params: [String: Any], required: [String]) -> [String: Any] {
        ["type": "function",
         "function": ["name": name, "description": desc,
                      "parameters": ["type": "object", "properties": params, "required": required]]]
    }

    private func param(_ type: String, _ desc: String) -> [String: String] {
        ["type": type, "description": desc]
    }

    private func formatSize(_ bytes: Int) -> String {
        bytes < 1_024 ? "\(bytes) B" : bytes < 1_048_576 ? "\(bytes / 1_024) KB" : "\(bytes / 1_048_576) MB"
    }
}
