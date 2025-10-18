//
//  ContentView.swift
//  Snapchat Memory Jar
//
//  Created by armaan badhan on 18/10/25.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var selectedFolder: URL?
    @Published var lastImportError: String?
    @Published var isImporting: Bool = false

    // Parsed conversations: conversationID -> [Message]
    @Published var conversations: [String: [Message]] = [:]

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

struct ContentView: View {

    @StateObject private var appState = AppState()

    var body: some View {
        NavigationView{
            ListView()
                .environmentObject(appState)
            MainView()
                .environmentObject(appState)
        }
        .frame(minWidth: 400, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    presentFolderPicker()
                } label: {
                    Label("Choose Export Folder", systemImage: "folder")
                }
            }
        }
    }

    private func presentFolderPicker() {
        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowedContentTypes = [.folder]
            panel.prompt = "Choose"
            panel.title = "Choose the unzipped Snapchat export folder"

            let response = panel.runModal()
            guard response == .OK, let url = panel.url else { return }

            appState.isImporting = true
            appState.lastImportError = nil
            defer { appState.isImporting = false }

            do {
                guard url.hasDirectoryPath else {
                    throw NSError(domain: "Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Please choose a folder (not a file)."])
                }

                appState.selectedFolder = url

                // Load conversations from json/chat_history.json
                let loader = SnapchatExportLoader()
                let conversations = try await loader.load(from: appState.selectedFolder)
                appState.conversations = conversations

                // Compute orphan media after we have conversations loaded
                appState.refreshOrphanMedia()

                // If nothing selected yet, default to Memories if it has content, else first conversation (alphabetical)
                if appState.selectedConversationID == nil {
                    if !appState.orphanMedia.isEmpty {
                        appState.selectedConversationID = AppState.memoriesID
                    } else {
                        appState.selectedConversationID = conversations.keys.sorted().first
                    }
                }
            } catch {
                appState.lastImportError = error.localizedDescription
                appState.conversations = [:]
                appState.orphanMedia = []
                appState.selectedConversationID = nil
            }
        }
    }
}

struct ListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View{
        VStack(alignment: .leading, spacing: 8) {
            if let folder = appState.selectedFolder {
                Text("Selected export folder:")
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if appState.isImporting {
                    ProgressView("Loading…")
                        .padding(.top, 8)
                } else if let error = appState.lastImportError {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.top, 8)
                } else if appState.conversations.isEmpty && appState.orphanMedia.isEmpty {
                    Text("No conversations or media found.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    List(selection: Binding(
                        get: {
                            appState.selectedConversationID.map { Set([$0]) } ?? []
                        },
                        set: { newSelection in
                            appState.selectedConversationID = newSelection.first
                        })
                    ) {
                        // Memories row at the top
                        HStack {
                            Label("Memories", systemImage: "photo.on.rectangle.angled")
                            Spacer()
                            Text("\(appState.orphanMedia.count)")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .tag(AppState.memoriesID)
                        .onTapGesture {
                            appState.selectedConversationID = AppState.memoriesID
                        }
                        .help("Images in chat_media that are not referenced by any conversation")

                        Section("Conversations") {
                            ForEach(sortedConversationIDs, id: \.self) { convoID in
                                let count = appState.conversations[convoID]?.count ?? 0
                                HStack {
                                    Text(convoID)
                                        .font(.body.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text("\(count)")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .tag(convoID)
                                .onTapGesture {
                                    appState.selectedConversationID = convoID
                                }
                                .help("Conversation ID: \(convoID)\nMessages: \(count)")
                            }
                        }
                    }
                    .frame(minHeight: 200)
                }
            } else {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
                Text("Use the toolbar button to choose the unzipped Snapchat export folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var sortedConversationIDs: [String] {
        appState.conversations.keys.sorted()
    }
}

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View{
        VStack(spacing: 12) {
            if appState.isImporting {
                ProgressView("Loading…")
            }

            if let error = appState.lastImportError {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if appState.selectedConversationID == AppState.memoriesID {
                MemoriesView(imageURLs: appState.orphanMedia)
            } else if let convoID = appState.selectedConversationID,
                      let messages = appState.conversations[convoID], !messages.isEmpty {
                ConversationView(conversationID: convoID, messages: messages)
                    .environmentObject(appState)
            } else if appState.selectedFolder != nil && appState.lastImportError == nil && !appState.isImporting {
                Text("Select a conversation to view messages.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct MemoriesView: View {
    let imageURLs: [URL]

    // Simple grid for images
    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memories")
                .font(.headline)
            Divider()
            if imageURLs.isEmpty {
                Text("No unreferenced media found in chat_media.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(imageURLs, id: \.self) { url in
                            if let img = NSImage(contentsOf: url) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(minWidth: 120, maxWidth: 240, minHeight: 120)
                                    .clipped()
                                    .cornerRadius(8)
                                    .overlay(alignment: .bottomLeading) {
                                        Text(url.lastPathComponent)
                                            .font(.caption2)
                                            .padding(4)
                                            .background(.thinMaterial)
                                            .cornerRadius(4)
                                            .padding(4)
                                    }
                                    .contextMenu {
                                        Button("Reveal in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                    }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.15))
                                    Text(url.lastPathComponent)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .padding(6)
                                }
                                .frame(minWidth: 120, minHeight: 120)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var appState: AppState

    let conversationID: String
    let messages: [Message]

    private var sortedMessages: [Message] {
        messages.sorted {
            // Sort by microseconds if present, else by createdDate, else fallback to string compare to stabilize
            if let a = $0.createdMicroseconds, let b = $1.createdMicroseconds {
                return a < b
            }
            if let ad = $0.createdDate, let bd = $1.createdDate {
                return ad < bd
            }
            return ($0.createdStringUTC ?? "") < ($1.createdStringUTC ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversation")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(conversationID)
                .font(.headline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedMessages) { msg in
                        MessageRow(message: msg)
                            .environmentObject(appState)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var appState: AppState
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Simple bubble alignment: right if isSender == true
            if message.isSender == true { Spacer(minLength: 20) }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(senderText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let dateText = dateString {
                        Text("• \(dateText)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Group {
                    if let imageURL = imageFileURL(),
                       let nsImage = NSImage(contentsOf: imageURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 320, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if let media = message.mediaType, media.lowercased() != "text" {
                        Text(mediaDisplay(media, ids: message.mediaIDs))
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                    } else {
                        Text(message.content ?? "(no content)")
                            .font(.body)
                    }
                }
                .padding(0.8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(maxWidth: 400, alignment: .leading)

            if message.isSender != true { Spacer(minLength: 20) }
        }
        .padding(.horizontal, 4)
    }

    private var senderText: String {
        if let isSender = message.isSender {
            return isSender ? (message.from ?? "You") : (message.from ?? "Unknown")
        }
        return message.from ?? "Unknown"
    }

    private var dateString: String? {
        if let d = message.createdDate {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: d)
        }
        return message.createdStringUTC
    }

    private var bubbleBackground: some ShapeStyle {
        if message.isSender == true {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }
    }

    private func mediaDisplay(_ media: String, ids: String?) -> String {
        if let ids, !ids.isEmpty {
            return "[\(media) • IDs: \(ids)]"
        }
        return "[\(media)]"
    }

    // Attempts to find an image file corresponding to the message's media IDs.
    // Strategy:
    // - Look inside "<exportFolder>/chat_media"
    // - For each candidate media ID (split by pipes or commas), search for a file whose filename contains the ID
    // - Check common image extensions
    private func imageFileURL() -> URL? {
        guard let base = appState.selectedFolder else { return nil }
        let mediaFolder = base.appendingPathComponent("chat_media", isDirectory: true)

        let ids = mediaIDsList()
        let fm = FileManager.default

        // If folder missing, bail
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: mediaFolder.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        // Try direct file existence for common extensions with exact "<id>.<ext>" naming
        let exts = ["jpg", "jpeg", "png", "heic", "gif", "bmp", "tiff", "webp"]
        for id in ids {
            for ext in exts {
                let candidate = mediaFolder.appendingPathComponent("\(id).\(ext)")
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        // Fallback: scan directory and match filenames that contain the ID
        guard let enumerator = fm.enumerator(at: mediaFolder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent.lowercased()
            if !exts.contains(fileURL.pathExtension.lowercased()) { continue }
            for id in ids {
                if name.contains(id.lowercased()) {
                    return fileURL
                }
            }
        }

        return nil
    }

    private func mediaIDsList() -> [String] {
        // mediaIDs can be separated by pipes "|" or commas ","
        let raw = message.mediaIDs ?? ""
        if raw.isEmpty { return [] }

        let separators = CharacterSet(charactersIn: "|,")
        let parts = raw
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return parts
    }
}

#Preview {
    ContentView()
}
