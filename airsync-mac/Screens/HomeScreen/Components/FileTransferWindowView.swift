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
                VStack(spacing: 24) {
                    
                    // Header removed - set as window title instead

                    // Circular Progress Area
                    ZStack {
                        // Background Ring
                        Circle()
                            .stroke(lineWidth: 8)
                            .opacity(0.15)
                            .foregroundColor(isFailed ? .red : .primary)
                        
                        // Progress Ring
                        Circle()
                            .trim(from: 0.0, to: CGFloat(progress))
                            .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                            .foregroundColor(isFailed ? .red : .blue)
                            .rotationEffect(Angle(degrees: 270.0))
                            .animation(.linear, value: progress)
                        
                        // Center Content
                        ZStack(alignment: .bottom) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 42))
                                .foregroundColor(isFailed ? .red : .primary.opacity(0.8))
                                .offset(y: -4)
                            
                            HStack(spacing: 4) {
                                Image(systemName: session.direction == .outgoing ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 11, weight: .bold))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 2)
                            .offset(y: 20)
                        }
                    }
                    .frame(width: 140, height: 140)
 
                    // File Name
                    VStack(spacing: 6) {
                        Text(session.name)
                            .font(.system(size: 14, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal)
                            .opacity(0.8)
                        
                        if !isCompleted && !isFailed {
                            if let eta = session.estimatedTimeRemaining {
                                Text(formatTime(eta))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Calculating...")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                        
                    // Actions
                    HStack(spacing: 12) {
                        if isCompleted {
                            if session.direction == .incoming {
                                GlassButtonView(label: "Open", systemImage: "arrow.up.forward.app", size:.large) {
                                    openFile(session.name)
                                }
                                GlassButtonView(label: "Locate", systemImage: "folder", size:.large) {
                                    locateFile(session.name)
                                }
                            }
                            
                            GlassButtonView(
                                label: "Done",
                                systemImage: "checkmark",
                                size:.large,
                                primary: true
                            ) {
                                appState.clearActiveTransfer()
                            }
                        } else if isFailed {
                            GlassButtonView(label: "Close", systemImage: "xmark", size:.large) {
                                appState.clearActiveTransfer()
                            }
                        } else {
                            // In Progress
                            GlassButtonView(label: "Hide", systemImage: "eye.slash", size:.large) {
                                appState.activeTransferId = nil
                            }
                            
                            GlassButtonView(label: "Cancel", systemImage: "xmark.circle.fill", size:.large) {
                                appState.cancelTransfer(id: session.id)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.bottom, 20)
                }
                .padding(24)
            } else {
                 Color.clear
                    .onAppear {
                        dismissWindow()
                    }
            }
        }
        .onAppear {
            NSWindow.allowsAutomaticWindowTabbing = false
        }
        .onChange(of: appState.activeTransferId) { _, newValue in
            if newValue == nil {
                dismissWindow()
            }
        }
        .background(FileTransferWindowAccessor(title: headerText, callback: { window in
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
            window.isReleasedWhenClosed = false
            window.titleVisibility = .visible
            window.title = headerText
        }))
    }
    
    private var headerText: String {
        guard let s = session, let deviceName = appState.device?.name else { return "File Transfer" }
        return s.direction == .outgoing ? "Sending to \(deviceName)..." : "Receiving from \(deviceName)..."
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs remaining", seconds)
        } else {
            let mins = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return String(format: "%dm %02ds remaining", mins, secs)
        }
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
    var title: String
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

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

