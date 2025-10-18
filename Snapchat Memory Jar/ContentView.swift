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

    // Currently selected conversation
    @Published var selectedConversationID: String?
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

                // If nothing selected yet, default to the first conversation (alphabetical)
                if appState.selectedConversationID == nil {
                    appState.selectedConversationID = conversations.keys.sorted().first
                }
            } catch {
                appState.lastImportError = error.localizedDescription
                appState.conversations = [:]
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
                } else if appState.conversations.isEmpty {
                    Text("No conversations found in json/chat_history.json")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    List(selection: Binding(
                        get: { appState.selectedConversationID.map { Set([ $0 ]) } ?? [] },
                        set: { newSelection in
                            appState.selectedConversationID = newSelection.first
                        })
                    ) {
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

            if let convoID = appState.selectedConversationID,
               let messages = appState.conversations[convoID], !messages.isEmpty {
                ConversationView(conversationID: convoID, messages: messages)
            } else if appState.selectedFolder != nil && appState.lastImportError == nil && !appState.isImporting {
                Text("Select a conversation to view messages.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct ConversationView: View {
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
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct MessageRow: View {
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
                    if let media = message.mediaType, media.lowercased() != "text" {
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
}

#Preview {
    ContentView()
}
