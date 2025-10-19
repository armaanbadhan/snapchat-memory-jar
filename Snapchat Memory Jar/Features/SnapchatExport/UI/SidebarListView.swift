//
//  SidebarListView.swift
//  Snapchat Memory Jar
//

import SwiftUI

struct SidebarListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
