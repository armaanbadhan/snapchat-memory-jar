# Snapchat Memory Jar (macOS)

A macOS SwiftUI app to browse your exported Snapchat chats and media locally. Select your unzipped Snapchat export folder to see:
- A list of conversations (from json/chat_history.json)
- Messages for the selected conversation
- Inline display of image media found in the chat_media folder
- A “Memories” section listing images present in chat_media that are not referenced by any conversation

## Requirements
- macOS 13 or later
- Xcode 15 or later
- Swift 5.9+

## Getting Started

1. Open the project in Xcode.
2. Build and run the app on macOS.
3. Click the toolbar button “Choose Export Folder” and select your unzipped Snapchat export folder.

Expected folder structure inside your selected folder:
- json/chat_history.json
- chat_media/ (contains images with filenames that include media IDs)

Example:
