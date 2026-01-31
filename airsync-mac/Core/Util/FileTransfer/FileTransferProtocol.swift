import Foundation
import CryptoKit

enum FileTransferProtocol {
    static func buildInit(id: String, name: String, size: Int64, mime: String, chunkSize: Int, checksum: String?, isClipboard: Bool = false) -> String {
        let checksumLine = (checksum?.isEmpty == false) ? ",\n        \"checksum\": \"\(checksum!)\"" : ""
        return """
        {
            "type": "fileTransferInit",
            "data": {
                "id": "\(id)",
                "name": "\(name)",
                "size": \(size),
                "mime": "\(mime)",
                "chunkSize": \(chunkSize),
                "isClipboard": \(isClipboard)\(checksumLine)
            }
        }
        """
    }

    static func buildChunk(id: String, index: Int, base64Chunk: String) -> String {
        return """
        {
            "type": "fileChunk",
            "data": {
                "id": "\(id)",
                "index": \(index),
                "chunk": "\(base64Chunk)"
            }
        }
        """
    }

    static func buildComplete(id: String, name: String, size: Int64, checksum: String?) -> String {
        let checksumLine = (checksum?.isEmpty == false) ? ",\n                \"checksum\": \"\(checksum!)\"" : ""
        return """
        {
            "type": "fileTransferComplete",
            "data": {
                "id": "\(id)",
                "name": "\(name)",
                "size": \(size)\(checksumLine)
            }
        }
        """
    }

    static func buildChunkAck(id: String, index: Int) -> String {
        return """
        {
            "type": "fileChunkAck",
            "data": { "id": "\(id)", "index": \(index) }
        }
        """
    }

    static func buildTransferVerified(id: String, verified: Bool) -> String {
        return """
        {
            "type": "transferVerified",
            "data": { "id": "\(id)", "verified": \(verified) }
        }
        """
    }

    static func buildFilePull(path: String) -> String {
        return """
        {
            "type": "filePull",
            "data": { "path": "\(path)" }
        }
        """
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
