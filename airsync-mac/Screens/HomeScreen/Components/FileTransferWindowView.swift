import SwiftUI

struct FileTransferWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) var dismissWindow

    private var session: AppState.FileTransferSession? {
        guard let id = appState.activeTransferId else { return nil }
        return appState.transfers[id]
    }

    private var isCompleted: Bool {
        if let status = session?.status {
            if case .completed = status { return true }
        }
        return false
    }

    private var isFailed: Bool {
        if let status = session?.status {
            if case .failed = status { return true }
        }
        return false
    }

    private var progress: Double {
        session?.progress ?? 0
    }

    var body: some View {
        ZStack {
            if let session = session {
                VStack(spacing: 20) {
                    
                    // Circular Progress
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 6)
                            .opacity(0.3)
                            .foregroundColor(isFailed ? .red : .gray)
                        
                        Circle()
                            .trim(from: 0.0, to: CGFloat(progress))
                            .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                            .foregroundColor(isFailed ? .red : .blue)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.linear, value: progress)
                        
                        // File Icon
                        Image(systemName: "doc.fill")
                            .font(.system(size: 40))
                            .foregroundColor(isFailed ? .red : .primary)
                    }
                    .frame(width: 80, height: 80)
                    .padding(.top, 10)

                    // File Info
                    VStack(spacing: 8) {
                        Text(session.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Actions
                    HStack(spacing: 16) {
                        if isCompleted {
                            if session.direction == .incoming {
                                GlassButtonView(label: "Open", systemImage: "arrow.up.forward.app") {
                                    openFile(session.name)
                                }
                                GlassButtonView(label: "Locate", systemImage: "folder") {
                                    locateFile(session.name)
                                }
                            }
                            
                            GlassButtonView(label: "Done", systemImage: "checkmark", primary: true) {
                                appState.clearActiveTransfer()
                            }
                        } else if isFailed {
                            GlassButtonView(label: "Close", systemImage: "xmark") {
                                appState.clearActiveTransfer()
                            }
                        } else {
                            // In Progress
                            GlassButtonView(label: "Hide", systemImage: "eye.slash") {
                                appState.activeTransferId = nil // Just hide window, transfer continues
                            }
                            
                            GlassButtonView(label: "Cancel", systemImage: "xmark.circle.fill") {
                                appState.cancelTransfer(id: session.id)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.bottom, 10)
                }
                .padding(24)
            } else {
                 Color.clear
                    .onAppear {
                        dismissWindow()
                    }
            }
        }
        .frame(width: 320, height: 300)
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
        }
        .onChange(of: appState.activeTransferId) { _, newValue in
            if newValue == nil {
                dismissWindow()
            }
        }
        .background(FileTransferWindowAccessor(callback: { window in
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            window.isReleasedWhenClosed = false
        }))
    }
    
    private var statusText: String {
        guard let s = session else { return "" }
        if isFailed {
            if case .failed(let reason) = s.status { return "Failed: \(reason)" }
            return "Failed"
        }
        if isCompleted {
            return "Transfer Complete"
        }
        let sizeMB = Double(s.size) / 1024.0 / 1024.0
        let transferredMB = Double(s.bytesTransferred) / 1024.0 / 1024.0
        let percent = Int(progress * 100)
        return String(format: "%.1f / %.1f MB (%d%%)", transferredMB, sizeMB, percent)
    }
    
    private func openFile(_ filename: String) {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let fileURL = downloads.appendingPathComponent(filename)
            NSWorkspace.shared.open(fileURL)
        }
        // Dismiss after action? User might want to locate too. Keep open.
    }
    
    private func locateFile(_ filename: String) {
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
             let fileURL = downloads.appendingPathComponent(filename)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }
}

struct FileTransferWindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let nsView = NSView()
        DispatchQueue.main.async {
            if let window = nsView.window {
                self.callback(window)
            }
        }
        return nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

