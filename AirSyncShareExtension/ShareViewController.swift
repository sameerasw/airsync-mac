import AppKit

final class ShareViewController: NSViewController {
    private lazy var detail = NSTextField(wrappingLabelWithString: "AirSync will send this to your connected device or let you pick one.")
    private lazy var sendButton = NSButton(title: "Send with AirSync", target: self, action: #selector(send))
    private lazy var cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    private var sendTask: Task<Void, Never>?

    init() {
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 360, height: 150)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        let title = NSTextField(wrappingLabelWithString: "Send with AirSync")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        detail.textColor = .secondaryLabelColor
        sendButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [sendButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, detail, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        view = content
    }

    @objc private func send() {
        guard sendTask == nil else { return }
        sendButton.isEnabled = false
        detail.stringValue = "Preparing this share for AirSync..."
        sendTask = Task { @MainActor in
            await handOff()
        }
    }

    private func handOff() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let group = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.sameerasw.airsync-mac.widget"
              ) else {
            showError("AirSync could not access the shared items.")
            return
        }

        let loader = ShareInputLoader(groupContainer: group)
        var openingStarted = false
        do {
            let urls = try await loader.prepare(items)
            try Task.checkCancellation()
            detail.stringValue = "Opening AirSync..."
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.allowsRunningApplicationSubstitution = false
            openingStarted = true
            _ = try await NSWorkspace.shared.open(
                urls,
                withApplicationAt: appURL,
                configuration: configuration
            )
            try Task.checkCancellation()
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch is CancellationError {
            if !openingStarted { loader.discard() }
        } catch {
            if !openingStarted { loader.discard() }
            if !Task.isCancelled { showError(error.localizedDescription) }
        }
    }

    private func showError(_ message: String) {
        detail.stringValue = message
        sendButton.isEnabled = true
        cancelButton.isEnabled = true
        sendTask = nil
    }

    @objc private func cancel() {
        guard cancelButton.isEnabled else { return }
        sendTask?.cancel()
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}
