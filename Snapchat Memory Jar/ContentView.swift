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

//     Parsed conversations: conversationID -> [Message]
    @Published var conversations: [String: [Message]] = [:]
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

//                 Load conversations from json/chat_history.json
                let loader = SnapchatExportLoader()
                let conversations = try await loader.load(from: appState.selectedFolder)
                appState.conversations = conversations
            } catch {
                appState.lastImportError = error.localizedDescription
                appState.conversations = [:]
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
                    List {
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
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
