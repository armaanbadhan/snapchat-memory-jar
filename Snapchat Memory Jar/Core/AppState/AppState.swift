//
//  AppState.swift
//  Snapchat Memory Jar
//

import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var lastImportError: String?
    @Published var isImporting: Bool = false

    // Parsed conversations: conversationID -> [SnapchatMessage]
    @Published var conversations: [String: [SnapchatMessage]] = [:]

    // Currently selected conversation (or the special "Memories" id)
    @Published var selectedConversationID: String?

    // URLs of media in chat_media not referenced by any conversation
    @Published var orphanMedia: [URL] = []

    // Special ID representing the "Memories" synthetic collection
    static let memoriesID = "__MEMORIES__"

    func refreshOrphanMedia() {
        guard let base = selectedFolder else {
            orphanMedia = []
            return
        }
        let mediaFolder = base.appendingPathComponent("chat_media", isDirectory: true)
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: mediaFolder.path, isDirectory: &isDir), isDir.boolValue else {
            orphanMedia = []
            return
        }

        // Gather all referenced media IDs from conversations
        let referencedIDs: Set<String> = conversations.values
            .flatMap { $0 }
            .flatMap { msg -> [String] in
                guard let raw = msg.mediaIDs, !raw.isEmpty else { return [] }
                let separators = CharacterSet(charactersIn: "|,")
                return raw
                    .components(separatedBy: separators)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            }
            .reduce(into: Set<String>()) { $0.formUnion([$1]) }

        // Enumerate media files and keep those that don't match any referenced ID
        let exts = ["jpg", "jpeg", "png", "heic", "gif", "bmp", "tiff", "webp"]
        var results: [URL] = []

        if let enumerator = fm.enumerator(at: mediaFolder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                let ext = fileURL.pathExtension.lowercased()
                guard exts.contains(ext) else { continue }
                let name = fileURL.lastPathComponent.lowercased()

                // If any referenced ID is contained in the filename, it's not an orphan
                let matchesReferenced = referencedIDs.contains { id in name.contains(id) }
                if !matchesReferenced {
                    results.append(fileURL)
                }
            }
        }

        // Sort by filename for stability
        orphanMedia = results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
