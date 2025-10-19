//
//  ContentView.swift
//  Snapchat Memory Jar
//
//  Created by armaan badhan on 18/10/25.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {

    @StateObject private var appState = AppState()

    var body: some View {
        NavigationView {
            SidebarListView()
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

#Preview {
    ContentView()
}
