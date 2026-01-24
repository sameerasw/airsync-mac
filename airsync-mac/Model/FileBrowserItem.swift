import Foundation

struct FileBrowserItem: Codable, Identifiable {
    var id: String { name }
    let name: String
    let isDir: Bool
    let size: Int64
    let time: Int64
    
    var formattedSize: String {
        if isDir { return "--" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(time / 1000))
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
