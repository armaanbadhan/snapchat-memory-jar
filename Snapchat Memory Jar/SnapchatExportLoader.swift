import Foundation
import UniformTypeIdentifiers

struct Message: Codable, Identifiable, Sendable {
    // Synthetic ID for SwiftUI lists
    var id: String { "\(conversationID ?? "unknown")-\(createdMicroseconds ?? 0)-\(from ?? "")-\(content ?? "")" }

    let from: String?
    let mediaType: String?
    let createdStringUTC: String?
    let content: String?
    let conversationTitle: String?
    let isSender: Bool?
    let createdMicroseconds: Int64?
    let isSaved: Bool?
    let mediaIDs: String?

    // Derived
    let createdDate: Date?
    // Filled by the loader when we know which conversation key this message came from
    var conversationID: String?

    enum CodingKeys: String, CodingKey {
        case from = "From"
        case mediaType = "Media Type"
        case createdStringUTC = "Created"
        case content = "Content"
        case conversationTitle = "Conversation Title"
        case isSender = "IsSender"
        case createdMicroseconds = "Created(microseconds)"
        case isSaved = "IsSaved"
        case mediaIDs = "Media IDs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try container.decodeIfPresent(String.self, forKey: .from)
        self.mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        self.createdStringUTC = try container.decodeIfPresent(String.self, forKey: .createdStringUTC)
        self.content = try container.decodeIfPresent(String.self, forKey: .content)
        self.conversationTitle = try container.decodeIfPresent(String.self, forKey: .conversationTitle)
        self.isSender = try container.decodeIfPresent(Bool.self, forKey: .isSender)
        self.createdMicroseconds = try container.decodeIfPresent(Int64.self, forKey: .createdMicroseconds)
        self.isSaved = try container.decodeIfPresent(Bool.self, forKey: .isSaved)
        self.mediaIDs = try container.decodeIfPresent(String.self, forKey: .mediaIDs)

        // Parse to Date, preferring microseconds (more precise), falling back to Created string.
        if let us = createdMicroseconds {
            // Snapchat uses microseconds since Unix epoch
            self.createdDate = Date(timeIntervalSince1970: TimeInterval(us) / 1_000_000.0)
        } else if let createdStr = createdStringUTC {
            self.createdDate = Message.utcDateFormatter.date(from: createdStr)
        } else {
            self.createdDate = nil
        }

        self.conversationID = nil
    }

    // Custom encoder to preserve original keys; derived fields are not encoded.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(from, forKey: .from)
        try container.encodeIfPresent(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(createdStringUTC, forKey: .createdStringUTC)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(conversationTitle, forKey: .conversationTitle)
        try container.encodeIfPresent(isSender, forKey: .isSender)
        try container.encodeIfPresent(createdMicroseconds, forKey: .createdMicroseconds)
        try container.encodeIfPresent(isSaved, forKey: .isSaved)
        try container.encodeIfPresent(mediaIDs, forKey: .mediaIDs)
    }

    // Static UTC formatter matching "yyyy-MM-dd HH:mm:ss UTC"
    private static let utcDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return df
    }()
}

final class SnapchatExportLoader {
    enum LoaderError: Error, LocalizedError {
        case folderMissing
        case fileNotFound(URL)
        case unreadableData(URL)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .folderMissing:
                return "No export folder selected."
            case .fileNotFound(let url):
                return "Could not find JSON file at \(url.path)."
            case .unreadableData(let url):
                return "Could not read data from \(url.path)."
            case .decodingFailed(let error):
                return "Failed to decode JSON: \(error.localizedDescription)"
            }
        }
    }

    // Top-level shape: conversationID -> [Message]
    typealias ConversationMap = [String: [Message]]

    func load(from exportFolder: URL?) async throws -> ConversationMap {
        guard let exportFolder else { throw LoaderError.folderMissing }

        let fileURL = exportFolder
            .appendingPathComponent("json", isDirectory: true)
            .appendingPathComponent("chat_history.json", conformingTo: .json)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LoaderError.fileNotFound(fileURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LoaderError.unreadableData(fileURL)
        }

        let decoder = JSONDecoder()
        // Default decoding; keys are exact so no key strategy needed.

        do {
            var conversations = try decoder.decode(ConversationMap.self, from: data)

            // Inject conversationID into each message and ensure createdDate is present (already computed in init).
            for (key, messages) in conversations {
                let updated = messages.map { msg -> Message in
                    var m = msg
                    m.conversationID = key
                    return m
                }
                conversations[key] = updated
            }

            return conversations
        } catch {
            throw LoaderError.decodingFailed(error)
        }
    }
}
