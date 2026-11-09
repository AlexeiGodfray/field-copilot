// Downloads Kokoro-82M, the open voice model the app reads results aloud with, into FieldCopilot/Kokoro.
// The app bundles that folder, so the voice works offline. It's 88 MB, so it stays out of git.
//
// Run from the repository root, then rebuild the app:
//   swift FieldCopilot/Scripts/fetch_voice.swift
//
// Source: huggingface.co/aufklarer/Kokoro-82M-CoreML-INT8, Kokoro-82M (Apache-2.0) converted to Core ML
// with 8-bit weights, at one fixed revision so every build gets the same voice.

import Foundation

let here = URL(filePath: #filePath).deletingLastPathComponent()
let output = here.appending(path: "../Kokoro").standardizedFileURL
let repository = "aufklarer/Kokoro-82M-CoreML-INT8"
let revision = "4ef656f55554ceb242ed11febbdbbffd60dd5938"

/// What the app loads: the voice model, the pronunciation models and dictionaries, and the voices.
let wanted = ["kokoro_5s.mlmodelc/", "G2PEncoder.mlmodelc/", "G2PDecoder.mlmodelc/", "voices/",
              "vocab_index.json", "g2p_vocab.json", "us_gold.json", "us_silver.json"]

struct Entry: Decodable {
    let type: String
    let path: String
}

func get(_ url: URL) async throws -> (URL, URLResponse) {
    let (file, response) = try await URLSession.shared.download(from: url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw URLError(.badServerResponse, userInfo: [NSURLErrorFailingURLStringErrorKey: url.absoluteString])
    }
    return (file, response)
}

let (listing, _) = try await get(URL(string: "https://huggingface.co/api/models/\(repository)/tree/\(revision)?recursive=true")!)
let files = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: listing)).filter { entry in
    entry.type == "file" && wanted.contains { $0.hasSuffix("/") ? entry.path.hasPrefix($0) : entry.path == $0 }
}
for file in files {
    let (download, _) = try await get(URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(file.path)")!)
    let destination = output.appending(path: file.path)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: download, to: destination)
    print(file.path)
}
print("Saved \(files.count) files to FieldCopilot/Kokoro")
