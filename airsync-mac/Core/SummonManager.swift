//
//  SummonManager.swift
//  airsync-mac
//
//  "Summon" pulls things from the paired Android device to the Mac on demand,
//  starting with a screenshot. Currently only works while connected via ADB.
//

import Foundation
import AppKit

class SummonManager {
    static let shared = SummonManager()

    private init() {}

    func summonScreenshot() {
        guard AppState.shared.adbConnected else {
            presentNotConnectedAlert()
            return
        }

        ADBConnector.summonScreenshot { [weak self] data in
            guard let self = self else { return }
            guard let data = data else {
                DispatchQueue.main.async {
                    self.presentFailureAlert()
                }
                return
            }
            DispatchQueue.main.async {
                self.handleSummonedScreenshot(data: data)
            }
        }
    }

    private func handleSummonedScreenshot(data: Data) {
        guard let downloadsDirectory = try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).resolvingSymlinksInPath() else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let initialDest = downloadsDirectory.appendingPathComponent("Screenshot \(dateFormatter.string(from: Date())).png")
        let dest = makeUniqueDestinationURL(initialDest)

        do {
            try data.write(to: dest)
        } catch {
            print("[summon] Failed to write screenshot: \(error)")
            presentFailureAlert()
            return
        }

        copyToClipboard(imageData: data)

        if AppState.shared.showSummonedFiles {
            SharedImagePopupManager.shared.show(fileURL: dest)
        }
    }

    private func copyToClipboard(imageData: Data) {
        guard let image = NSImage(data: imageData) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func makeUniqueDestinationURL(_ initialDest: URL) -> URL {
        var dest = initialDest
        if FileManager.default.fileExists(atPath: dest.path) {
            var counter = 1
            var path: String
            let ext = dest.pathExtension
            let baseUrl = dest.deletingPathExtension()
            repeat {
                path = "\(baseUrl.path) (\(counter))"
                if !ext.isEmpty {
                    path += ".\(ext)"
                }
                counter += 1
            } while FileManager.default.fileExists(atPath: path)
            dest = URL(fileURLWithPath: path)
        }
        return dest
    }

    private func presentNotConnectedAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Summon Unavailable"
        alert.informativeText = "Connect via ADB to use Summon."
        alert.addButton(withTitle: "OK")
        presentAlertAsynchronously(alert)
    }

    private func presentFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Summon Failed"
        alert.informativeText = "Couldn't capture a screenshot from the device. Check the ADB Console in Settings for details."
        alert.addButton(withTitle: "OK")
        presentAlertAsynchronously(alert)
    }

    private func presentAlertAsynchronously(_ alert: NSAlert) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.isKeyWindow && $0.isVisible }) ?? NSApp.windows.first(where: { $0.isVisible }) {
                alert.beginSheetModal(for: window)
            } else {
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }
}
