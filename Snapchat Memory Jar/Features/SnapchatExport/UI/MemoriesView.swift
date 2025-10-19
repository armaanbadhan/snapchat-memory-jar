//
//  MemoriesView.swift
//  Snapchat Memory Jar
//

import SwiftUI
import AppKit

struct MemoriesView: View {
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
