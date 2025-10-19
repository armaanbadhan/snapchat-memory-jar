//
//  MainView.swift
//  Snapchat Memory Jar
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
