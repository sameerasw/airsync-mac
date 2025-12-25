import Foundation

/// Represents a connected remote viewer/client (e.g., an Android device session).
/// This definition intentionally stays minimal; extend as needed if other code requires more fields.
struct RemoteViewerClientModel: Identifiable, Hashable, Codable {
    static let shared = RemoteViewerClientModel()
    
    /// Stable identifier for the client.
    var id: UUID = UUID()

    /// Optional display name for the client/device.
    var name: String?

    /// IP address of the client if applicable.
    var ipAddress: String?

    /// Port used for the connection, if available.
    var port: Int?

    init(id: UUID = UUID(), name: String? = nil, ipAddress: String? = nil, port: Int? = nil) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.port = port
    }
}
