import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct SharePreviewItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let icon: NSImage
    let thumbnail: NSImage?
    let byteCount: Int64?
    let isFolder: Bool
}

@MainActor
struct SharePreviewLoader {
    static let thumbnailByteLimit: Int64 = 25 * 1024 * 1024
    private let thumbnailSize = CGSize(width: 96, height: 96)

    func load(_ items: [NSExtensionItem]) async -> [SharePreviewItem] {
        var previews: [SharePreviewItem] = []
        for item in items {
            let attachments = item.attachments ?? []
            if attachments.isEmpty {
                if let text = item.attributedContentText?.string, !text.isEmpty {
                    previews.append(textPreview(text, name: "Shared Text"))
                }
            } else {
                for provider in attachments {
                    if let preview = await preview(provider) {
                        previews.append(preview)
                    }
                }
            }
        }
        return previews
    }

    private func preview(_ provider: NSItemProvider) async -> SharePreviewItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await loadURL(provider) {
            return url.isFileURL ? await filePreview(url) : linkPreview(url)
        }

        let identifiers = provider.registeredTypeIdentifiers
        if let imageType = identifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            return await imagePreview(provider, typeIdentifier: imageType)
        }
        if let fileType = identifiers.first(where: {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
        }) {
            let type = UTType(fileType)
            return SharePreviewItem(
                name: provider.suggestedName ?? "Shared Item",
                detail: type?.localizedDescription ?? "File",
                icon: type.map { NSWorkspace.shared.icon(for: $0) } ?? NSImage(named: NSImage.multipleDocumentsName) ?? NSImage(),
                thumbnail: nil,
                byteCount: nil,
                isFolder: false
            )
        }
        if let textType = identifiers.first(where: { UTType($0)?.conforms(to: .text) == true }),
           let data = try? await loadData(provider, typeIdentifier: textType),
           let text = String(data: data, encoding: .utf8) {
            return textPreview(text, name: provider.suggestedName ?? "Shared Text")
        }
        return nil
    }

    private func filePreview(_ url: URL) async -> SharePreviewItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .localizedTypeDescriptionKey])
        let isFolder = values?.isDirectory == true || url.hasDirectoryPath
        let size = values?.fileSize.map(Int64.init)
        let kind = values?.localizedTypeDescription ?? "File"
        let icon = NSWorkspace.shared.icon(forFile: url.path)

        var thumbnail: NSImage?
        if !isFolder, let size, size <= Self.thumbnailByteLimit {
            thumbnail = await quickLookThumbnail(url)
        }
        return SharePreviewItem(
            name: url.lastPathComponent,
            detail: isFolder ? "Folder" : [kind, size.map(Self.format)].compactMap { $0 }.joined(separator: " · "),
            icon: icon,
            thumbnail: thumbnail,
            byteCount: isFolder ? nil : size,
            isFolder: isFolder
        )
    }

    private func imagePreview(_ provider: NSItemProvider, typeIdentifier: String) async -> SharePreviewItem? {
        guard let data = try? await loadData(provider, typeIdentifier: typeIdentifier) else { return nil }
        let size = Int64(data.count)
        let type = UTType(typeIdentifier)
        return SharePreviewItem(
            name: provider.suggestedName ?? "Shared Image",
            detail: [type?.localizedDescription ?? "Image", Self.format(size)].joined(separator: " · "),
            icon: type.map { NSWorkspace.shared.icon(for: $0) } ?? NSImage(),
            thumbnail: size <= Self.thumbnailByteLimit ? downsampled(data) : nil,
            byteCount: size,
            isFolder: false
        )
    }

    private func linkPreview(_ url: URL) -> SharePreviewItem {
        SharePreviewItem(
            name: url.host ?? url.absoluteString,
            detail: url.absoluteString,
            icon: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage(),
            thumbnail: nil,
            byteCount: Int64(url.absoluteString.utf8.count),
            isFolder: false
        )
    }

    private func textPreview(_ text: String, name: String) -> SharePreviewItem {
        let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return SharePreviewItem(
            name: name,
            detail: String(snippet.prefix(120)),
            icon: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil) ?? NSImage(),
            thumbnail: nil,
            byteCount: Int64(text.utf8.count),
            isFolder: false
        )
    }

    private func quickLookThumbnail(_ url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private func downsampled(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailSize.width * 2,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = url as? NSURL {
                    continuation.resume(returning: url as URL)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private func loadData(_ provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    nonisolated static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
