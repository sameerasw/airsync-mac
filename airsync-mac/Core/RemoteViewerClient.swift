import Foundation

/// A lightweight representation of a connected remote viewer client (e.g., an Android device session)
/// This is intentionally minimal to satisfy existing references. Extend as needed if other files
/// require additional properties or behavior.
struct RemoteViewerClient: Identifiable, Hashable, Codable {
    /// Stable identifier for the client. If the upstream code expects a different ID type,
    /// it can be updated later.
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
