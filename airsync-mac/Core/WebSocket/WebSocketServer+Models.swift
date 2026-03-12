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
        var id: String
        var name: String
        var size: Int
        var mime: String
        var tempUrl: URL
        var fileHandle: FileHandle?
        var chunkSize: Int
        var bytesReceived: Int = 0
    }
}
