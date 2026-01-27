//
//  WebSocketServer+Models.swift
//  airsync-mac
//

import Foundation
import Swifter

enum WebSocketStatus {
    case stopped
    case starting
    case started(port: UInt16, ip: String?)
    case failed(error: String)
}

extension WebSocketServer {
    struct IncomingFileIO {
        var tempUrl: URL
        var fileHandle: FileHandle?
        var chunkSize: Int
    }
}
