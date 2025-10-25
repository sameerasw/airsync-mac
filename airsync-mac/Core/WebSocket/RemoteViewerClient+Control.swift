import Foundation
import Cocoa

extension RemoteViewerConnection {
    private static var viewerController: RemoteViewerWindowController?

    func start(ip: String) {
        Self.start(ip: ip)
    }

    func stop() {
        Self.stop()
    }

    static func start(ip: String) {
        let port = AppState.shared.device?.port ?? 12345
        print("RemoteViewerClient starting with ip: \(ip), port: \(port)")
        DispatchQueue.main.async {
            if viewerController == nil {
                viewerController = RemoteViewerWindowController(host: ip, port: UInt16(port))
            }
            viewerController?.showWindow(nil)
            viewerController?.window?.makeKeyAndOrderFront(nil)
        }
    }

    static func stop() {
        print("RemoteViewerClient stopping")
        DispatchQueue.main.async {
            viewerController?.window?.close()
            viewerController = nil
        }
    }
}
