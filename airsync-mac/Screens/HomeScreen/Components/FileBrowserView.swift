import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var appState = AppState.shared
    let onClose: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    GlassButtonView(
                        label: "Back",
                        systemImage: "chevron.left",
                        iconOnly: true,
                        action: {
                            appState.navigateUp()
                        }
                    )
                    .disabled(appState.browsePath == "/sdcard/" || appState.browsePath == "/sdcard")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Browser")
                            .font(.headline)
                        Text(appState.browsePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.leading, 8)
                    
                    Spacer()


                    GlassButtonView(
                        label: "More",
                        systemImage: "ellipsis",
                        iconOnly: true,
                        action: {
                            // more context menu
                        }
                    )

                    if appState.isBrowsingLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    } else {

                        GlassButtonView(
                            label: "Refresh",
                            systemImage: "arrow.clockwise",
                            iconOnly: true,
                            action: {
                                appState.fetchDirectory(path: appState.browsePath)
                            }
                        )
                    }

                    GlassButtonView(
                        label: "Close",
                        action: {
                            onClose()
                        }
                    )
                    .padding(.leading, 8)
                }
                .padding()
                
                // Content
                if let error = appState.browseError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .padding()
                        GlassButtonView(label: "Try Again") {
                            appState.fetchDirectory(path: appState.browsePath)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.browseItems.isEmpty && !appState.isBrowsingLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No items found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(appState.browseItems) { item in
                            FileBrowserItemRow(item: item) {
                                if item.isDir {
                                    let cleanPath = appState.browsePath.hasSuffix("/") ? appState.browsePath : appState.browsePath + "/"
                                    let newPath = cleanPath + item.name + "/"
                                    appState.fetchDirectory(path: newPath)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .listStyle(.sidebar)
                }
            }
        }
        .frame(width: 500, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 20)
    }
}

struct FileBrowserItemRow: View {
    let item: FileBrowserItem
    let onNavigate: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: item.isDir ? "folder.fill" : fileIcon(for: item.name))
                .foregroundColor(item.isDir ? .accentColor : .secondary)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(item.formattedDate)
                    if !item.isDir {
                        Text("•")
                        Text(item.formattedSize)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if item.isDir {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onNavigate()
        }
        // Also single tap for folders to make it easier
        .onTapGesture(count: 1) {
            if item.isDir {
                onNavigate()
            }
        }
        .listRowSeparator(.hidden)
    }
    
    private func fileIcon(for name: String) -> String {
        let ext = name.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "jpg", "jpeg", "png", "gif", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "video"
        case "mp3", "wav", "m4a", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "rar", "7z", "gz": return "archivebox"
        case "apk": return "app.badge"
        case "txt", "md": return "doc.text"
        default: return "doc"
        }
    }
}
