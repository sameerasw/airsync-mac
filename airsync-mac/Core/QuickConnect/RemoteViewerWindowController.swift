import Cocoa

@MainActor
class RemoteViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let host: String
    private let port: UInt16

    private var client: RemoteViewerConnection?
    private var displayView: RemoteDisplayView?
    private var timeLabel: NSTextField?
    private var timeTimer: Timer?

    init(host: String, port: UInt16 = 12345) {
        self.host = host
        self.port = port

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Screen - \(host)"
        window.center()

        super.init(window: window)
        window.delegate = self

        // Add top toolbar with Disconnect button
        let topToolbar = NSToolbar(identifier: "RemoteViewerToolbar")
        topToolbar.delegate = self
        topToolbar.displayMode = .iconOnly
        window.toolbar = topToolbar

        setupUI(host: host, port: port)
    }

    required init?(coder: NSCoder) {
        // Provide safe defaults for Interface Builder / coder init
        self.host = "localhost"
        self.port = 12345
        super.init(coder: coder)
        // If a window is already loaded via coder, finish setup
        if let w = self.window {
            w.title = "Android Screen - \(host)"
            w.delegate = self

            // Add top toolbar with Disconnect button
            let topToolbar = NSToolbar(identifier: "RemoteViewerToolbar")
            topToolbar.delegate = self
            topToolbar.displayMode = .iconOnly
            w.toolbar = topToolbar
        }
        setupUI(host: host, port: port)
    }

    private func setupUI(host: String, port: UInt16) {
        guard let window = window else { return }

        let contentView = NSView()
        window.contentView = contentView

        let toolbar = createToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        let displayView = RemoteDisplayView(frame: .zero)
        displayView.translatesAutoresizingMaskIntoConstraints = false

        // Ensure explicit z-order so the toolbar always stays above the display view
        displayView.wantsLayer = true
        displayView.layer?.zPosition = 0
        toolbar.wantsLayer = true
        toolbar.layer?.zPosition = 1000
        toolbar.layer?.masksToBounds = false

        // Add display first, then toolbar so toolbar stays on top
        contentView.addSubview(displayView)
        contentView.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            displayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            displayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            displayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            displayView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
        ])

        self.displayView = displayView

        let client = RemoteViewerConnection()
        displayView.setClient(client)
        client.connect(to: host, port: port)
        self.client = client
    }

    private func createToolbar() -> NSView {
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 44))
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // Create a full-width stack view to host the three navigation buttons
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .equalCentering
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        // Constrain stack to take the full width of the toolbar with padding
        let padding: CGFloat = 16
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -padding),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            stack.heightAnchor.constraint(equalTo: toolbar.heightAnchor)
        ])

        func makeIconButton(systemName: String, title: String, action: Selector) -> NSButton {
            let button = NSButton(title: "", target: self, action: action)
            button.bezelStyle = .rounded
            button.image = NSImage(systemSymbolName: systemName, accessibilityDescription: title)
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setButtonType(.momentaryPushIn)
            button.translatesAutoresizingMaskIntoConstraints = false
            // Slightly larger symbols for easier click targets
            let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            if let configuredImage = button.image?.withSymbolConfiguration(config) {
                button.image = configuredImage
            }
            // Give buttons a consistent intrinsic size
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return button
        }

        // Android-style bottom navigation: Back, Home, Recents
        let back = makeIconButton(systemName: "chevron.backward", title: "Back", action: #selector(backButtonPressed))
        let home = makeIconButton(systemName: "house", title: "Home", action: #selector(homeButtonPressed))
        let recents = makeIconButton(systemName: "rectangle.on.rectangle", title: "Recents", action: #selector(recentButtonPressed))

        stack.addArrangedSubview(back)
        stack.addArrangedSubview(home)
        stack.addArrangedSubview(recents)

        return toolbar
    }

    @objc private func backButtonPressed() {
        client?.sendBackButton()
    }

    @objc private func homeButtonPressed() {
        client?.sendHomeButton()
    }

    @objc private func recentButtonPressed() {
        client?.sendRecentApps()
    }

    @objc private func disconnectButtonPressed() {
        client?.disconnect()
        close()
    }

    @objc func windowWillClose(_ notification: Foundation.Notification) {
        client?.disconnect()
        timeTimer?.invalidate()
        timeTimer = nil
    }

    private func startTimeUpdates() {
        timeTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTimeLabel()
            }
        }
        timeTimer = timer
        // Update immediately on start
        updateTimeLabel()
    }

    private func updateTimeLabel() {
        guard let label = timeLabel else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        label.stringValue = formatter.string(from: Date())
    }
}

extension NSToolbarItem.Identifier {
    static let disconnect = NSToolbarItem.Identifier("DisconnectToolbarItem")
}

extension RemoteViewerWindowController {
    // MARK: - NSToolbarDelegate
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .disconnect]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Place Disconnect on the right by preceding with a flexible space
        return [.flexibleSpace, .disconnect]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .disconnect:
            let item = NSToolbarItem(itemIdentifier: .disconnect)
            item.label = "Disconnect"
            item.paletteLabel = "Disconnect"
            item.toolTip = "Disconnect from device"
            item.target = self
            item.action = #selector(disconnectButtonPressed)
            if let image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Disconnect") {
                item.image = image
            }
            return item
        default:
            return nil
        }
    }
}
