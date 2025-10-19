//
//  ConversationView.swift
//  Snapchat Memory Jar
//

import SwiftUI

struct ConversationView: View {
    @EnvironmentObject private var appState: AppState

    let conversationID: String
    let messages: [SnapchatMessage]

    private var sortedMessages: [SnapchatMessage] {
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
