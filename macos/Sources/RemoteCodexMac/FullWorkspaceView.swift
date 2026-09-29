import SwiftUI
import WebKit

/// Full relay feature surface for advanced tools not yet duplicated natively.
/// Session cookies are copied only to an ephemeral, origin-bound WebKit store.
struct FullWorkspaceView: NSViewRepresentable {
    let url: URL
    let cookies: [HTTPCookie]
    let reportError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(origin: url, reportError: reportError) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        context.coordinator.load(web, url: url, cookies: cookies)
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.requestedURL != url { context.coordinator.load(web, url: url, cookies: cookies) }
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) { web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let origin: URL
        let reportError: (String) -> Void
        var requestedURL: URL?
        init(origin: URL, reportError: @escaping (String) -> Void) { self.origin = origin; self.reportError = reportError }
        func load(_ web: WKWebView, url: URL, cookies: [HTTPCookie]) {
            requestedURL = url
            Task { @MainActor [weak web] in
                guard let web else { return }
                for cookie in cookies { await web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) }
                if self.requestedURL == url { web.load(URLRequest(url: url)) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = action.request.url else { decisionHandler(.cancel); return }
            let sameOrigin = target.scheme == origin.scheme && target.host == origin.host && target.port == origin.port
            if sameOrigin { decisionHandler(action.shouldPerformDownload ? .download : .allow); return }
            if target.scheme == "blob", action.shouldPerformDownload,
               target.absoluteString.hasPrefix("blob:" + origin.scheme! + "://" + origin.host! + (origin.port.map { ":\($0)" } ?? "") + "/") { decisionHandler(.download); return }
            if action.navigationType == .linkActivated, ["https", "http"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, let target = action.request.url,
               target.scheme == origin.scheme, target.host == origin.host, target.port == origin.port { webView.load(action.request) }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { reportError(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = parameters.allowsMultipleSelection; panel.canChooseDirectories = parameters.allowsDirectories
            panel.begin { result in completionHandler(result == .OK ? panel.urls : nil) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .download)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let panel = NSSavePanel(); panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
            panel.begin { answer in completionHandler(answer == .OK ? panel.url : nil) }
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { reportError(error.localizedDescription) }
    }
}
