import Foundation
import UniformTypeIdentifiers

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

    // Top-level shape: conversationID -> [SnapchatMessage]
    typealias ConversationMap = [String: [SnapchatMessage]]

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

        do {
            var conversations = try decoder.decode(ConversationMap.self, from: data)

            // Inject conversationID into each message (createdDate is computed in SnapchatMessage.init)
            for (key, messages) in conversations {
                let updated = messages.map { msg -> SnapchatMessage in
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
