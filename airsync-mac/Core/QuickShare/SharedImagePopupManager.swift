//
//  SharedImagePopupManager.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-05-21.
//

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import Combine
import ImageIO
import AVFoundation

// MARK: - File Type Classification

enum SharedFileType {
    case image
    case video
    case other
}

func getSharedFileType(for url: URL) -> SharedFileType {
    let ext = url.pathExtension.lowercased()
    let imageExts = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "avif", "svg"]
    let videoExts = ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "flv", "webm", "ts", "3gp"]
    if imageExts.contains(ext) { return .image }
    if videoExts.contains(ext) { return .video }
    if let uti = UTType(filenameExtension: ext) {
        if uti.conforms(to: .image) { return .image }
        if uti.conforms(to: .movie) || uti.conforms(to: .video) { return .video }
    }
    return .other
}


// MARK: - High Performance Image Helpers

func generateLowQualityThumbnail(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: .zero)
}

// MARK: - Video Thumbnail Helper

func generateVideoThumbnail(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

    let times: [CMTime] = [CMTime(seconds: 1, preferredTimescale: 600), .zero]
    for t in times {
        if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
            return NSImage(cgImage: cg, size: .zero)
        }
    }
    return nil
}


// MARK: - File Metadata Helpers

func getFileSizeString(at url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey])
    guard let bytes = values?.fileSize else { return "" }
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

func getFileIconAndColor(for url: URL) -> (String, Color) {
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "pdf": return ("doc.richtext", .red)
    case "zip", "rar", "7z", "tar", "gz": return ("archivebox", .orange)
    case "mp3", "aac", "flac", "wav", "ogg", "m4a": return ("waveform", .purple)
    case "txt", "md", "rtf": return ("doc.text", .blue)
    case "csv", "xlsx", "xls", "numbers": return ("tablecells", Color(red: 0.2, green: 0.7, blue: 0.3))
    case "doc", "docx", "pages": return ("doc.fill", .blue)
    case "ppt", "pptx", "key": return ("rectangle.on.rectangle", .orange)
    case "dmg", "pkg", "app": return ("shippingbox", .gray)
    case "swift", "kt", "py", "js", "ts", "html", "css", "json", "xml": return ("chevron.left.forwardslash.chevron.right", .cyan)
    case "apk": return ("iphone.gen1", Color(red: 0.4, green: 0.8, blue: 0.4))
    default:
        if let uti = UTType(filenameExtension: ext) {
            if uti.conforms(to: .audio) { return ("waveform", .purple) }
            if uti.conforms(to: .archive) { return ("archivebox", .orange) }
        }
        return ("doc", .secondary)
    }
}

// MARK: - Data Model

public struct SharedImageInfo: Identifiable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let addedAt: Date

    public init(id: UUID = UUID(), fileURL: URL, addedAt: Date = Date()) {
        self.id = id
        self.fileURL = fileURL
        self.addedAt = addedAt
    }
}

// MARK: - Custom AppKit Drag & Drop View Wrapper

struct FileDraggableView: NSViewRepresentable {
    let fileURL: URL
    let thumbnailImage: NSImage?
    let onDragStarted: () -> Void
    let onDragEnded: (Bool) -> Void

    func makeNSView(context: Context) -> DraggableNSView {
        let view = DraggableNSView()
        view.fileURL = fileURL
        view.thumbnailImage = thumbnailImage
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DraggableNSView, context: Context) {
        nsView.fileURL = fileURL
        nsView.thumbnailImage = thumbnailImage
    }

    class DraggableNSView: NSView, NSDraggingSource {
        var fileURL: URL?
        var thumbnailImage: NSImage?
        var onDragStarted: (() -> Void)?
        var onDragEnded: ((Bool) -> Void)?

        override func mouseDown(with event: NSEvent) {
            guard let fileURL = fileURL else { return }

            DispatchQueue.main.async {
                self.onDragStarted?()
            }

            let draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)

            // Use pre-rendered thumbnail if available, otherwise fallback to workspace icon
            var dragImage: NSImage = thumbnailImage ?? NSWorkspace.shared.icon(forFile: fileURL.path)
            let maxDragSize = NSSize(width: 120, height: 120)
            if dragImage.size.width > maxDragSize.width || dragImage.size.height > maxDragSize.height {
                let ratio = dragImage.size.width / dragImage.size.height
                let newSize: NSSize = ratio > 1
                    ? NSSize(width: maxDragSize.width, height: maxDragSize.width / ratio)
                    : NSSize(width: maxDragSize.height * ratio, height: maxDragSize.height)
                let resized = NSImage(size: newSize)
                resized.lockFocus()
                dragImage.draw(in: NSRect(origin: .zero, size: newSize), from: .zero, operation: .copy, fraction: 1.0)
                resized.unlockFocus()
                dragImage = resized
            }

            draggingItem.setDraggingFrame(
                NSRect(x: event.locationInWindow.x - dragImage.size.width / 2,
                       y: event.locationInWindow.y - dragImage.size.height / 2,
                       width: dragImage.size.width,
                       height: dragImage.size.height),
                contents: dragImage
            )

            self.beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            return .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DispatchQueue.main.async { [weak self] in
                let success = operation.rawValue != 0
                self?.onDragEnded?(success)
            }
        }
    }
}

// MARK: - Manager

@MainActor
public class SharedImagePopupManager: NSObject, ObservableObject {
    public static let shared = SharedImagePopupManager()

    @Published public var activeImages: [SharedImageInfo] = []

    private var window: NSPanel?
    private var dismissTimer: Timer?

    private var windowHeight: CGFloat {
        let count = activeImages.count
        if count <= 1 {
            return 200
        } else {
            return CGFloat(130 + (count - 1) * 80 + 40)
        }
    }

    private override init() {
        super.init()
    }

    public func show(fileURL: URL) {
        let limit = AppState.shared.sharedImagePopupsLimit

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            while self.activeImages.count >= limit {
                self.activeImages.removeFirst()
            }
            let newImage = SharedImageInfo(fileURL: fileURL)
            self.activeImages.append(newImage)
        }

        self.resetTimer()

        if self.window == nil {
            let windowWidth: CGFloat = 300
            let h = self.windowHeight

            let screen = NSScreen.main ?? NSScreen.screens.first
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

            let onLeft = AppState.shared.popupSharedImagesOnLeft
            let targetX = onLeft ? screenFrame.minX : (screenFrame.maxX - windowWidth)
            let targetY = screenFrame.midY - (h / 2)

            let startFrame = NSRect(x: targetX, y: targetY, width: windowWidth, height: h)

            let panel = NSPanel(
                contentRect: startFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.alphaValue = 1.0

            let hostingView = NSHostingView(rootView: SharedImageOverlayView())
            hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: h)
            panel.contentView = hostingView

            self.window = panel
            panel.orderFrontRegardless()
        } else {
            self.updateWindowPosition()
        }
    }

    public func dismiss(imageID: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.activeImages.removeAll { $0.id == imageID }
        }

        if self.activeImages.isEmpty {
            self.cancelTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self else { return }
                if self.activeImages.isEmpty {
                    self.window?.close()
                    self.window = nil
                }
            }
        }
    }

    public func dismissAll() {
        self.cancelTimer()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.activeImages.removeAll()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            if self.activeImages.isEmpty {
                self.window?.close()
                self.window = nil
            }
        }
    }

    public func updateWindowPosition() {
        guard let panel = self.window else { return }
        let windowWidth: CGFloat = 300
        let h = self.windowHeight

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)

        let onLeft = AppState.shared.popupSharedImagesOnLeft
        let targetX = onLeft ? screenFrame.minX : (screenFrame.maxX - windowWidth)
        let targetY = screenFrame.midY - (h / 2)

        panel.setFrame(NSRect(x: targetX, y: targetY, width: windowWidth, height: h), display: true, animate: true)

        if let hostingView = panel.contentView as? NSHostingView<SharedImageOverlayView> {
            hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: h)
        }
    }

    private func resetTimer() {
        self.cancelTimer()
        self.dismissTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismissAll()
            }
        }
    }

    private func cancelTimer() {
        self.dismissTimer?.invalidate()
        self.dismissTimer = nil
    }
}

// MARK: - SwiftUI Main Overlay View

struct SharedImageOverlayView: View {
    @ObservedObject var manager = SharedImagePopupManager.shared
    @ObservedObject var appState = AppState.shared
    @State private var isDeckHovered = false
    @State private var hoveredCardID: UUID? = nil

    var body: some View {
        let onLeft = appState.popupSharedImagesOnLeft
        let isExpanded = isDeckHovered || hoveredCardID != nil

        ZStack(alignment: .bottom) {
            // Narrow edge strip — only the visible peeking area triggers deck expansion.
            // Placed BEHIND the cards so it does not block clicks, drags, or card-specific hover.
            if !manager.activeImages.isEmpty {
                HStack(spacing: 0) {
                    if !onLeft { Spacer(minLength: 0).allowsHitTesting(false) }
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 45) // Placed behind, generous 45px strip makes hover trigger incredibly easy and reliable
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                self.isDeckHovered = hovering
                            }
                        }
                    if onLeft { Spacer(minLength: 0).allowsHitTesting(false) }
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(true)
            }

            if !manager.activeImages.isEmpty {
                let images = manager.activeImages
                let count = images.count

                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    SharedImageCardView(
                        image: image,
                        index: index,
                        totalCount: count,
                        isDeckHovered: isExpanded,
                        onLeft: onLeft,
                        onHoverChanged: { isHovering in
                            if isHovering {
                                hoveredCardID = image.id
                            } else if hoveredCardID == image.id {
                                hoveredCardID = nil
                            }
                        },
                        onDismiss: {
                            manager.dismiss(imageID: image.id)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: onLeft ? .leading : .trailing).combined(with: .opacity),
                        removal: .move(edge: onLeft ? .leading : .trailing).combined(with: .opacity)
                    ))
                }
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - SwiftUI Individual Card View

struct SharedImageCardView: View {
    let image: SharedImageInfo
    let index: Int
    let totalCount: Int
    let isDeckHovered: Bool
    let onLeft: Bool
    let onHoverChanged: (Bool) -> Void
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var fileType: SharedFileType = .other
    @State private var thumbnailImage: NSImage? = nil
    @State private var fileSizeString: String = ""
    @State private var isLoading = true

    private var fileName: String {
        image.fileURL.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 0) {
            if onLeft {
                cardContent
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                            self.isHovered = hovering
                        }
                        onHoverChanged(hovering)
                    }
                    .padding(.leading, -offsetXBase)
                    .padding(.bottom, -offsetY)
                Spacer(minLength: 0).allowsHitTesting(false)
            } else {
                Spacer(minLength: 0).allowsHitTesting(false)
                cardContent
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                            self.isHovered = hovering
                        }
                        onHoverChanged(hovering)
                    }
                    .padding(.trailing, -offsetXBase)
                    .padding(.bottom, -offsetY)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .zIndex(Double(index))
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDeckHovered)
        .onAppear {
            DispatchQueue.global(qos: .userInteractive).async {
                let detectedType = getSharedFileType(for: image.fileURL)
                let sizeStr = getFileSizeString(at: image.fileURL)
                var thumb: NSImage? = nil

                switch detectedType {
                case .image:
                    thumb = generateLowQualityThumbnail(at: image.fileURL, maxPixelSize: 300)
                case .video:
                    thumb = generateVideoThumbnail(at: image.fileURL, maxPixelSize: 300)
                case .other:
                    break
                }

                DispatchQueue.main.async {
                    self.fileType = detectedType
                    self.thumbnailImage = thumb
                    self.fileSizeString = sizeStr
                    self.isLoading = false
                }
            }
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )

            // Overlay drag layer
            FileDraggableView(
                fileURL: image.fileURL,
                thumbnailImage: thumbnailImage,
                onDragStarted: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        self.isPressed = true
                    }
                },
                onDragEnded: { success in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                        self.isPressed = false
                    }
                    if success {
                        onDismiss()
                    }
                }
            )
            .frame(width: cardWidth, height: cardHeight)

            // Action buttons — above drag layer
            if isHovered {
                HStack(spacing: 6) {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects([image.fileURL as NSURL])
                        onDismiss()
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(L("quickshare.copy"))

                    Button(action: { onDismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(L("notifications.actions.dismiss"))
                }
                .padding(8)
                .transition(.scale.combined(with: .opacity))
                .zIndex(10)
            }
        }
        .rotationEffect(.degrees(rotation), anchor: onLeft ? .bottomLeading : .bottomTrailing)
    }

    @ViewBuilder
    private var cardBody: some View {
        switch fileType {
        case .image:
            imageCardBody
        case .video:
            videoCardBody
        case .other:
            fileCardBody
        }
    }

    // MARK: Image card
    @ViewBuilder
    private var imageCardBody: some View {
        ZStack(alignment: .bottom) {
            if let thumbnail = thumbnailImage {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Color(NSColor.windowBackgroundColor)
                    .overlay(ProgressView().controlSize(.small))
            } else {
                Color(NSColor.windowBackgroundColor)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    )
            }

            // Filename label at bottom
            fileNameLabel
        }
    }

    // MARK: Video card
    @ViewBuilder
    private var videoCardBody: some View {
        ZStack(alignment: .bottom) {
            if let thumbnail = thumbnailImage {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Color.black
                    .overlay(ProgressView().controlSize(.small).tint(.white))
            } else {
                Color.black
            }

            // Play overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.85), .black.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            fileNameLabel
        }
    }

    // MARK: Generic file card — solid opaque background, no transparency
    @ViewBuilder
    private var fileCardBody: some View {
        let (iconName, iconColor) = getFileIconAndColor(for: image.fileURL)
        ZStack(alignment: .bottom) {
            // Solid dark background — never transparent
            Color(NSColor.windowBackgroundColor)

            // Subtle color tint gradient
            LinearGradient(
                colors: [iconColor.opacity(0.25), iconColor.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                Spacer()

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundColor(iconColor)

                // File size
                if !fileSizeString.isEmpty {
                    Text(fileSizeString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            fileNameLabel
        }
    }

    // MARK: Filename label (always visible, always at bottom)
    private var fileNameLabel: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(truncatedFileName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var truncatedFileName: String {
        // Truncate middle if longer than ~24 chars to fit card width
        let name = fileName
        let limit = 26
        guard name.count > limit else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let halfLen = (limit - ext.count - 4) / 2
        if halfLen > 3 {
            let start = base.prefix(halfLen)
            let end = base.suffix(halfLen)
            return "\(start)...\(end).\(ext)"
        }
        return String(name.prefix(limit)) + "..."
    }

    // All cards are a fixed 1:1 square — consistent hitbox regardless of content type
    private let cardSize: CGFloat = 130
    private var cardWidth: CGFloat { cardSize }
    private var cardHeight: CGFloat { cardSize }

    private var baseY: CGFloat {
        let shiftIndex = totalCount - 1 - index
        let verticalSpacing = isDeckHovered ? 80.0 : 15.0
        return -CGFloat(shiftIndex) * verticalSpacing
    }

    private var baseRotation: Double {
        let shiftIndex = totalCount - 1 - index
        let base = 8.0 + Double(shiftIndex) * 3.0
        return onLeft ? base : -base
    }

    private var rotation: Double {
        if isPressed { return 0.0 }
        if isHovered { return onLeft ? 14.0 : -14.0 }
        return baseRotation
    }

    private var offsetXBase: CGFloat {
        if isPressed {
            return 15
        } else if isHovered {
            return 15
        } else if isDeckHovered {
            let shiftIndex = totalCount - 1 - index
            return max(10, 60 - CGFloat(shiftIndex) * 25)
        } else {
            let shiftIndex = totalCount - 1 - index
            return 75 + CGFloat(shiftIndex) * 8
        }
    }

    private var offsetY: CGFloat {
        let bottomPadding: CGFloat = 18.0
        if isPressed { return baseY - bottomPadding }
        if isHovered { return baseY - 20 - bottomPadding }
        return baseY - bottomPadding
    }
}
