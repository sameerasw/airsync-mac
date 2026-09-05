import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: URL
    @Binding var currentURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor

        webView.load(URLRequest(url: url))
        return webView
    }



    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the URL changes
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                DispatchQueue.main.async {
                    self.parent.currentURL = url
                }
            }

            // Inject CSS to remove body background
            let js = """
    var style = document.createElement('style');
    style.innerHTML = `
    
    body, html, .docs-wrapper,
    #background {
    background-color: transparent !important;
    background: none !important;
    transition:
    background-color 0.5s ease-in-out,
    background 0.5s ease-in-out,
    border 0.5s ease-in-out,
    box-shadow 0.5s ease-in-out !important;
    }
    
    `;
    document.head.appendChild(style);
    """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

    }
}
