import Foundation
import UniformTypeIdentifiers

struct ShareInputLoader {
    enum InputError: LocalizedError {
        case empty
        case unsupported
        case folder

        var errorDescription: String? {
            switch self {
            case .empty: "There is nothing to send."
            case .unsupported: "AirSync cannot read one of the shared items."
            case .folder: "AirSync cannot send folders yet."
            }
        }
    }

    private let requestDirectory: URL

    init(groupContainer: URL) {
        requestDirectory = groupContainer
            .appendingPathComponent("Library/Caches/AirSyncShares", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func prepare(_ items: [NSExtensionItem]) async throws -> [URL] {
        removeOldRequests()
        do {
            var urls: [URL] = []
            for item in items {
                let attachments = item.attachments ?? []
                if attachments.isEmpty {
                    if let text = item.attributedContentText?.string, !text.isEmpty {
                        urls.append(try stage(Data(text.utf8), name: "Shared Text.txt"))
                    }
                } else {
                    for provider in attachments {
                        urls.append(try await prepare(provider))
                    }
                }
            }
            guard !urls.isEmpty else { throw InputError.empty }
            return urls
        } catch {
            discard()
            throw error
        }
    }

    func discard() {
        try? FileManager.default.removeItem(at: requestDirectory)
    }

    private func prepare(_ provider: NSItemProvider) async throws -> URL {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await loadURL(provider) {
            if url.isFileURL {
                try checkForFolder(url)
                return url
            }
            return try stage(Data(url.absoluteString.utf8), name: "Shared Link.txt")
        }

        let fileType = provider.registeredTypeIdentifiers.first {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
        }
        if let fileType {
            do {
                return try await stageFile(provider, typeIdentifier: fileType)
            } catch InputError.folder {
                throw InputError.folder
            } catch {
                let data = try await loadData(provider, typeIdentifier: fileType)
                return try stage(data, name: fileName(provider.suggestedName, typeIdentifier: fileType))
            }
        }

        if let textType = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .text) == true
        }) {
            let data = try await loadData(provider, typeIdentifier: textType)
            return try stage(data, name: fileName(provider.suggestedName, typeIdentifier: textType, fallback: "Shared Text"))
        }
        throw InputError.unsupported
    }

    private func loadURL(_ provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = url as? NSURL {
                    continuation.resume(returning: url as URL)
                } else {
                    continuation.resume(throwing: InputError.unsupported)
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
                    continuation.resume(throwing: InputError.unsupported)
                }
            }
        }
    }

    private func stageFile(_ provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { source, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let source else {
                    continuation.resume(throwing: InputError.unsupported)
                    return
                }
                do {
                    try checkForFolder(source)
                    let name = fileName(suggestedName, typeIdentifier: typeIdentifier, fallback: source.lastPathComponent)
                    let destination = try destination(for: name)
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stage(_ data: Data, name: String) throws -> URL {
        let destination = try destination(for: name)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func destination(for name: String) throws -> URL {
        let itemDirectory = requestDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        return itemDirectory.appendingPathComponent(name)
    }

    private func fileName(_ suggestedName: String?, typeIdentifier: String, fallback: String = "Shared Item") -> String {
        let suggested = suggestedName ?? fallback
        let name = (suggested as NSString).lastPathComponent
        let safeName = name.isEmpty || name == "." || name == ".." ? fallback : name
        guard (safeName as NSString).pathExtension.isEmpty,
              let ext = UTType(typeIdentifier)?.preferredFilenameExtension else { return safeName }
        return "\(safeName).\(ext)"
    }

    private func checkForFolder(_ url: URL) throws {
        if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            throw InputError.folder
        }
    }

    private func removeOldRequests() {
        let root = requestDirectory.deletingLastPathComponent()
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for child in children where child != requestDirectory {
            if let values = try? child.resourceValues(forKeys: [.contentModificationDateKey]),
               let date = values.contentModificationDate, date < cutoff {
                try? FileManager.default.removeItem(at: child)
            }
        }
    }
}
