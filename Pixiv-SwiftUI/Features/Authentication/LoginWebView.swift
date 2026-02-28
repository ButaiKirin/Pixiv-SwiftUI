import Foundation
import SwiftUI
import WebKit

#if os(macOS)
private typealias Representable = NSViewRepresentable
#else
private typealias Representable = UIViewRepresentable
#endif

struct LoginWebView: Representable {
    let url: URL
    let onCallback: (String, [HTTPCookie]) -> Void

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        // Clear all previous cookies and website data before starting a clean login session
        let dataStore = WKWebsiteDataStore.nonPersistent()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        // Setup user agent to simulate a mobile app? Or leave it default?
        // Let's just use the default

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView

        init(_ parent: LoginWebView) {
            self.parent = parent
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "pixiv" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {

                    // We found the code callback. Now fetch cookies.
                    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                        let pixivCookies = cookies.filter { $0.domain.contains("pixiv.net") }

                        DispatchQueue.main.async {
                            self?.parent.onCallback(code, pixivCookies)
                        }
                    }
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }
    }
}
