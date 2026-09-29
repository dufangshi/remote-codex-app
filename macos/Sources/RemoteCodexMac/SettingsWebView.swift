import SwiftUI
import WebKit
import RemoteCodexCore

/// Only used by SharedSettingsView, never as a conversation renderer.
/// Session cookies are copied only to an ephemeral, origin-bound WebKit store.
struct SettingsWebView: NSViewRepresentable {
    let url: URL
    let cookies: [HTTPCookie]
    let reportError: (String) -> Void
    var browser: SettingsBrowser? = nil
    func makeCoordinator() -> Coordinator { Coordinator(origin: url, reportError: reportError, browser: browser) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if browser != nil {
            let label = String(decoding: try! JSONSerialization.data(withJSONObject: browser!.action, options: .fragmentsAllowed), as: UTF8.self)
            config.userContentController.addUserScript(WKUserScript(source: "const requestedAction = " + label + ";\n" + Self.observerScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            config.userContentController.add(context.coordinator, name: "workspaceState")
        }
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        if let browser {
            browser.web = web; browser.coordinator = context.coordinator
            context.coordinator.requestedURL = url
            context.coordinator.bootstrapping = true
            web.loadHTMLString("<!doctype html><meta charset=utf-8><title>Connecting</title>", baseURL: browser.origin)
        } else { context.coordinator.load(web, url: url, cookies: cookies) }
        return web
    }
    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.requestedURL != url { context.coordinator.load(web, url: url, cookies: cookies) }
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil
        web.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
        web.configuration.userContentController.removeScriptMessageHandler(forName: "workspaceState")
    }
    // Only public identity keys and named UI preferences cross this bridge. Never cookies,
    // auth tokens, arbitrary localStorage, file contents or conversation text.
    static let observerScript = #"""
    if (location.protocol === 'http:' || location.protocol === 'https:') {
      let busy = false, opened = false, sawDialog = false;
      const readPreferences = () => {
        const preferences = {};
        for (const key of ['remote-codex-theme-mode','remote-codex-font-size','remote-codex-default-backend','remote-codex-auto-collapse-completed-turns','remote-codex-show-reasoning-summaries','remote-codex.explorer-width']) {
          const value = localStorage.getItem(key); if(value !== null) preferences[key] = value;
        }
        return preferences;
      };
      const capturePreferences = () => window.webkit.messageHandlers.workspaceState.postMessage({preferences: readPreferences()});
      window.addEventListener('remote-codex-font-size', capturePreferences);
      document.addEventListener('change', capturePreferences);
      const launchSettings = () => {
        const dialog = document.querySelector('[role="dialog"],dialog[open]');
        if (dialog) {
          if (!sawDialog) {
            sawDialog = true;
            const style = document.createElement('style');
            style.textContent = 'html,body {background:transparent!important} body>* {visibility:hidden} [role="dialog"], [role="dialog"] *, dialog[open], dialog[open] *, [role="alertdialog"], [role="alertdialog"] *, [data-radix-popper-content-wrapper], [data-radix-popper-content-wrapper] * {visibility:visible}';
            document.head.append(style);
          }
          return;
        }
        if (sawDialog) { capturePreferences(); window.webkit.messageHandlers.workspaceState.postMessage({closed:true}); return; }
        if (opened) return;
        const button = [...document.querySelectorAll('button')].find(e => e.getAttribute('aria-label') === requestedAction);
        if (!button && requestedAction !== 'Open settings') {
          const tools = document.querySelector('[aria-label="Thread tools"][aria-expanded="false"]'); if(tools) tools.click();
        }
        if (button) { button.click(); opened = true; }
      };
      const observer = new MutationObserver(launchSettings);
      observer.observe(document.documentElement, {childList:true, subtree:true});
      launchSettings();
      const capture = async () => {
        if (busy) return; busy = true;
        try {
          const preferences = readPreferences();
          const pins = await new Promise((resolve, reject) => {
            const r = indexedDB.open('remote-codex-transport-v1', 1);
            r.onupgradeneeded = () => r.result.createObjectStore('identities');
            r.onerror = () => reject(r.error);
            r.onsuccess = () => {
              const db = r.result, tx = db.transaction('identities'), result = {};
              const cursor = tx.objectStore('identities').openCursor();
              cursor.onsuccess = () => { const c = cursor.result; if(c) { result[c.key] = c.value; c.continue(); } };
              tx.oncomplete = () => { db.close(); resolve(result); };
              tx.onerror = () => { db.close(); reject(tx.error); };
            };
          });
          window.webkit.messageHandlers.workspaceState.postMessage({href: location.href, profile: {preferences, pins}});
        } finally { busy = false; }
      };
      setInterval(() => capture().catch(() => {}), 1500);
      capture().catch(() => {});
    }
    """#
    static let bootstrapScript = #"""
      for (const [key,value] of Object.entries(preferences)) localStorage.setItem(key,value);
      await new Promise((resolve,reject) => {
        const r = indexedDB.open('remote-codex-transport-v1',1);
        r.onupgradeneeded = () => r.result.createObjectStore('identities');
        r.onerror = () => reject(r.error);
        r.onsuccess = () => {
          const db = r.result, tx = db.transaction('identities','readwrite');
          for(const [id,key] of Object.entries(pins)) tx.objectStore('identities').put(key,id);
          tx.oncomplete = () => {db.close();resolve(true);};
          tx.onerror = () => {db.close();reject(tx.error);};
        };
      });
      return true;
    """#
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
        let origin: URL
        let reportError: (String) -> Void
        var requestedURL: URL?
        weak var browser: SettingsBrowser?
        var bootstrapping = false
        var observingCookies = false
        init(origin: URL, reportError: @escaping (String) -> Void, browser: SettingsBrowser?) { self.origin = origin; self.reportError = reportError; self.browser = browser }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if !bootstrapping, message.frameInfo.isMainFrame, let source = message.frameInfo.request.url,
               BrowserPolicy.sameOrigin(source, origin), let body = message.body as? [String: Any],
               let preferences = body["preferences"] as? [String: String],
               preferences.allSatisfy({ SettingsBrowser.preferenceKeys.contains($0.key) && $0.value.count < 256 }) {
                browser?.persistPreferences(preferences)
            }
            if !bootstrapping, message.frameInfo.isMainFrame, let source = message.frameInfo.request.url,
               BrowserPolicy.sameOrigin(source, origin), let body = message.body as? [String: Any], body["closed"] as? Bool == true {
                browser?.closed = true; return
            }
            guard !bootstrapping, message.frameInfo.isMainFrame,
                  let source = message.frameInfo.request.url, BrowserPolicy.sameOrigin(source, origin),
                  let body = message.body as? [String: Any], let href = body["href"] as? String,
                  let location = URL(string: href), BrowserPolicy.sameOrigin(location, origin),
                  let profile = body["profile"] as? [String: Any], let pins = profile["pins"] as? [String: String],
                  let preferences = profile["preferences"] as? [String: String],
                  pins.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value.count < 512 }),
                  preferences.allSatisfy({ SettingsBrowser.preferenceKeys.contains($0.key) && $0.value.count < 256 }) else { return }
            browser?.remember(location)
            browser?.canGoBack = message.webView?.canGoBack ?? false; browser?.canGoForward = message.webView?.canGoForward ?? false
            Task { await browser?.persistProfile(["pins": pins, "preferences": preferences]) }
        }
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            if bootstrapping, let browser {
                Task { @MainActor in
                    do {
                        _ = try await web.callAsyncJavaScript(SettingsWebView.bootstrapScript, arguments: ["pins": browser.initialPins, "preferences": browser.initialPreferences], in: nil, contentWorld: .page)
                        bootstrapping = false
                        if let url = requestedURL { load(web, url: url, cookies: browser.cookies) }
                    } catch { browser.loading = false; reportError("Cannot restore encrypted workspace trust: \(error.localizedDescription)") }
                }
            } else {
                browser?.loading = false; if let url = web.url { browser?.remember(url) }
                if browser != nil, !observingCookies {
                    observingCookies = true
                    web.configuration.websiteDataStore.httpCookieStore.add(self)
                }
            }
        }
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard observingCookies, let client = browser?.client else { return }
            Task {
                let cookies = await cookieStore.allCookies()
                let session = cookies.first { $0.name == "remote_codex_relay_session" && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == origin.host && $0.path == "/" }
                do { try await client.syncBrowserSession(session?.value) }
                catch { reportError("Could not synchronize relay sign-in: \(error.localizedDescription)") }
            }
        }
        func webView(_ web: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { browser?.loading = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            browser?.loading = false; reportError("The workspace renderer stopped. Reload to reconnect; unsaved edits may need to be entered again.")
        }
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
            if bootstrapping, target.absoluteString == "about:blank" { decisionHandler(.allow); return }
            let sameOrigin = BrowserPolicy.sameOrigin(target, origin)
            if sameOrigin { decisionHandler(action.shouldPerformDownload ? .download : .allow); return }
            if target.scheme == "blob", action.shouldPerformDownload,
               target.absoluteString.hasPrefix("blob:" + origin.scheme! + "://" + origin.host! + (origin.port.map { ":\($0)" } ?? "") + "/") { decisionHandler(.download); return }
            if action.navigationType == .linkActivated, ["https", "http"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.targetFrame == nil, let target = action.request.url,
               BrowserPolicy.sameOrigin(target, origin) { webView.load(action.request) }
            return nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { browser?.loading = false; reportError(error.localizedDescription) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "OK"); alert.runModal(); completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert(); alert.messageText = message; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Continue")
            completionHandler(alert.runModal() == .alertSecondButtonReturn)
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
