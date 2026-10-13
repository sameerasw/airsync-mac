import AppKit
import SwiftUI

final class ShareViewController: NSViewController {
    private let model = ShareModel()
    private var sendTask: Task<Void, Never>?

    init() {
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 380, height: 215)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func loadView() {
        let host = NSHostingView(rootView: ShareView(
            model: model,
            cancel: { [weak self] in self?.cancel() }
        ))
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.contentView = host
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        } else {
            container.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: container.topAnchor),
                host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            model.isLoadingPreview = false
            return
        }
        send()
        Task { @MainActor in
            model.items = await SharePreviewLoader().load(items)
            model.isLoadingPreview = false
            resizeToFit()
        }
    }

    private func resizeToFit() {
        preferredContentSize = NSSize(width: 380, height: model.totalHeight)
    }

    private func send() {
        guard sendTask == nil else { return }
        model.phase = .working("Preparing this share for AirSync…")
        sendTask = Task { @MainActor in
            await handOff()
        }
    }

    private func handOff() async {
        defer { sendTask = nil }
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
            model.phase = .working("Opening AirSync…")
            let appURL = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            guard appURL.pathExtension == "app" else {
                throw CocoaError(.fileNoSuchFile)
            }
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
        model.phase = .failed(message)
        sendTask = nil
    }

    private func cancel() {
        sendTask?.cancel()
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }
}
