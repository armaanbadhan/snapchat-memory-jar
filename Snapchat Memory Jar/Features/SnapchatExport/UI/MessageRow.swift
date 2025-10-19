//
//  MessageRow.swift
//  Snapchat Memory Jar
//

import SwiftUI
import AppKit

struct MessageRow: View {
    @EnvironmentObject private var appState: AppState
    let message: SnapchatMessage

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
