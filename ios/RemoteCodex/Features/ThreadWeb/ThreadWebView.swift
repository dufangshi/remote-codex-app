import SwiftUI
import WebKit

struct ThreadScreen: View {
    let store: SessionStore
    let deviceId: String
    let threadId: String
    let themeMode: ThemeMode
    var sessionName: String?
    var onBack: () -> Void
    var onOpenNav: () -> Void
    var onOpenAccount: () -> Void
    var onLeave: (AppRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(
                title: "Thread",
                backLabel: "Back to workspaces",
                onBack: onBack,
                onOpenNav: onOpenNav,
                onOpenAccount: onOpenAccount,
                accountLabel: sessionName
            )
            Text("Thread")
                .font(.system(size: 1))
                .frame(height: 0)
                .opacity(0)
                .accessibilityIdentifier("threadTitle")
            ThreadWebView(
                store: store,
                deviceId: deviceId,
                threadId: threadId,
                themeMode: themeMode,
                onLeave: onLeave
            )
            .accessibilityIdentifier("threadWebView")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("threadScreen")
    }
}

struct SettingsScreen: View {
    let store: SessionStore
    let deviceId: String
    let themeMode: ThemeMode
    var sessionName: String?
    var onBack: () -> Void
    var onOpenNav: () -> Void
    var onOpenAccount: () -> Void
    var onLeave: (AppRoute) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProductHeader(
                title: "Settings",
                backLabel: "Back",
                onBack: onBack,
                onOpenNav: onOpenNav,
                onOpenAccount: onOpenAccount,
                accountLabel: sessionName
            )
            ThreadWebView(
                store: store,
                deviceId: deviceId,
                threadId: "",
                themeMode: themeMode,
                pagePath: "/relay-settings?nativeApp=1&relay=1",
                onLeave: onLeave,
                onNativeClose: onBack
            )
            .accessibilityIdentifier("settingsDialog")
        }
        .accessibilityIdentifier("settingsDialog")
    }
}

struct ThreadWebView: UIViewControllerRepresentable {
    let store: SessionStore
    let deviceId: String
    let threadId: String
    let themeMode: ThemeMode
    var pagePath: String? = nil
    let onLeave: (AppRoute) -> Void
    var onNativeClose: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> ThreadWebController {
        let controller = ThreadWebController()
        controller.accessibilityProbe.accessibilityIdentifier = "threadWebView"
        return controller
    }

    func updateUIViewController(_ controller: ThreadWebController, context: Context) {
        controller.onLeave = { route in
            DispatchQueue.main.async {
                onLeave(route)
            }
        }
        controller.onNativeClose = {
            DispatchQueue.main.async {
                onNativeClose?()
            }
        }
        controller.load(store: store, deviceId: deviceId, threadId: threadId, themeMode: themeMode, pagePath: pagePath)
    }
}

final class ThreadWebController: UIViewController, WKNavigationDelegate {
    let accessibilityProbe = UILabel()
    private var webView: WKWebView?
    var deviceId = ""
    var threadId = ""
    var onLeave: ((AppRoute) -> Void)?
    var onNativeClose: (() -> Void)?
    private var loadedKey = ""
    private var interceptLeaves = false
    private var lastInjection = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "threadScreen"
        accessibilityProbe.text = "Thread"
        accessibilityProbe.font = .systemFont(ofSize: 1)
        accessibilityProbe.textAlignment = .center
        accessibilityProbe.isHidden = true
        accessibilityProbe.isAccessibilityElement = true
        accessibilityProbe.accessibilityIdentifier = "threadWebView"
        accessibilityProbe.accessibilityLabel = "Thread"
        accessibilityProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accessibilityProbe)
        NSLayoutConstraint.activate([
            accessibilityProbe.topAnchor.constraint(equalTo: view.topAnchor),
            accessibilityProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accessibilityProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accessibilityProbe.heightAnchor.constraint(equalToConstant: 0),
        ])
    }

    func load(store: SessionStore, deviceId: String, threadId: String, themeMode: ThemeMode, pagePath: String? = nil) {
        self.deviceId = deviceId
        self.threadId = threadId
        let key = "\(deviceId)|\(threadId)|\(store.relayUrl)|\(pagePath ?? "")"
        guard key != loadedKey else { return }
        loadedKey = key
        interceptLeaves = false

        let scriptSource = Self.injectionJS(store: store, deviceId: deviceId, themeMode: themeMode)
        lastInjection = scriptSource
        let script: WKUserScript
        if #available(iOS 14.0, *) {
            script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
        } else {
            script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        }
        let controller = WKUserContentController()
        controller.addUserScript(script)
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        webView?.removeFromSuperview()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.alwaysBounceHorizontal = false
        web.scrollView.bounces = true
        web.accessibilityIdentifier = "threadWebView"
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        bindEdgeBackGesture(web)
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView = web

        let origin = store.relayUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = if let pagePath, !pagePath.isEmpty {
            "\(origin)\(pagePath.hasPrefix("/") ? pagePath : "/\(pagePath)")"
        } else {
            "\(origin)/devices/\(enc(deviceId))/threads/\(enc(threadId))?nativeApp=1&relay=1"
        }
        guard let url = URL(string: target) else { return }
        Self.installRelaySessionCookie(store: store, dataStore: config.websiteDataStore) { [weak self, weak web] in
            guard let self, self.loadedKey == key else { return }
            web?.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let path = webView.url?.path ?? ""
        if path.contains("/threads/") || path == "/relay-settings" {
            interceptLeaves = true
        }
        if !lastInjection.isEmpty {
            webView.evaluateJavaScript(lastInjection, completionHandler: nil)
        }
        bindEdgeBackGesture(webView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let webView {
            bindEdgeBackGesture(webView)
        }
    }

    private func bindEdgeBackGesture(_ web: WKWebView) {
        guard let edge = EdgeBackSupport.gesture else { return }
        web.scrollView.panGestureRecognizer.require(toFail: edge)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard interceptLeaves, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            decisionHandler(.allow)
            return
        }
        if url.path == "/__native/close" {
            decisionHandler(.cancel)
            let close = onNativeClose
            DispatchQueue.main.async { close?() }
            return
        }
        if url.path == "/relay-settings" {
            decisionHandler(.allow)
            return
        }
        // RelayGate may bounce to `/` or `/relay-portal` while the session cookie
        // is settling. Those are not user navigation back to Choose a device.
        if url.scheme == "about" || url.path.isEmpty || url.path == "/" || url.path == "/relay-portal" {
            decisionHandler(.allow)
            return
        }
        if let route = nativeRoute(for: url, deviceId: deviceId) {
            switch route {
            case .threadDetail(_, let id, _) where id == threadId:
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
                let leave = onLeave
                DispatchQueue.main.async {
                    leave?(route)
                }
                return
            }
        }
        decisionHandler(.allow)
    }

    private func enc(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func sessionCookie(store: SessionStore) -> HTTPCookie? {
        guard let origin = URL(string: store.relayUrl), let host = origin.host, !store.token.isEmpty else {
            return nil
        }
        func make(_ extra: [HTTPCookiePropertyKey: Any]) -> HTTPCookie? {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: "remote_codex_relay_session",
                .value: store.token,
                .path: "/",
                .domain: host,
                .originURL: origin,
            ]
            if origin.scheme?.lowercased() == "https" {
                props[.secure] = "TRUE"
            }
            extra.forEach { props[$0] = $1 }
            return HTTPCookie(properties: props)
        }
        if #available(iOS 13.0, *) {
            if let cookie = make([.sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax]) {
                return cookie
            }
        }
        return make([:])
    }

    private static func installRelaySessionCookie(
        store: SessionStore,
        dataStore: WKWebsiteDataStore,
        completion: @escaping () -> Void
    ) {
        guard let origin = URL(string: store.relayUrl) else {
            completion()
            return
        }
        let group = DispatchGroup()
        if let existing = HTTPCookieStorage.shared.cookies(for: origin) {
            for cookie in existing where cookie.name != "remote_codex_relay_session" {
                group.enter()
                dataStore.httpCookieStore.setCookie(cookie) { group.leave() }
            }
        }
        if let cookie = sessionCookie(store: store) {
            HTTPCookieStorage.shared.setCookie(cookie)
            group.enter()
            dataStore.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private static func injectionJS(store: SessionStore, deviceId: String, themeMode: ThemeMode) -> String {
        let secure = store.relayUrl.lowercased().hasPrefix("https://") ? "; Secure" : ""
        return """
        window.__REMOTE_CODEX_BOOTSTRAP__ = Object.assign(
          { mode: 'relay', relayApiBase: '/relay' },
          window.__REMOTE_CODEX_BOOTSTRAP__ || {}
        );
        (function () {
          if (window.__REMOTE_CODEX_NATIVE_SESSION__) return;
          window.__REMOTE_CODEX_NATIVE_SESSION__ = true;
          var token = \(jsString(store.token));
          try {
            document.cookie = 'remote_codex_relay_session=' + token + '; path=/; SameSite=Lax\(secure)';
            localStorage.setItem('remote-codex-relay-mode', 'true');
            localStorage.removeItem('remote-codex-relay-token');
            localStorage.setItem('remote-codex-relay-device-id', \(jsString(deviceId)));
            localStorage.setItem('remote-codex-theme-mode', \(jsString(themeMode.rawValue)));
            localStorage.setItem('remote-codex-auto-collapse-completed-turns', \(jsString(store.autoCollapseCompletedTurns ? "true" : "false")));
          } catch (e) {}
          try {
            var origFetch = window.fetch.bind(window);
            window.fetch = function (input, init) {
              try {
                if (token && input instanceof Request) {
                  if (!input.headers.has('Authorization')) {
                    var headers = new Headers(input.headers);
                    headers.set('Authorization', 'Bearer ' + token);
                    return origFetch(new Request(input, { headers: headers }));
                  }
                  return origFetch(input);
                }
                var nextHeaders = new Headers((init && init.headers) || {});
                if (token && !nextHeaders.has('Authorization')) {
                  nextHeaders.set('Authorization', 'Bearer ' + token);
                }
                return origFetch(input, Object.assign({}, init || {}, {
                  headers: nextHeaders,
                  credentials: (init && init.credentials) || 'same-origin'
                }));
              } catch (err) {
                return origFetch(input, init);
              }
            };
          } catch (e) {}
          try {
            var fake = {
              postMessage: function () {},
              scriptURL: (location.origin || '') + '/',
              state: 'activated',
              addEventListener: function () {},
              removeEventListener: function () {},
              onstatechange: null
            };
            var dummyReg = {
              installing: null,
              waiting: null,
              active: fake,
              scope: (location.origin || '') + '/',
              update: function () { return Promise.resolve(); },
              unregister: function () { return Promise.resolve(true); },
              addEventListener: function () {},
              removeEventListener: function () {}
            };
            var swShim = {
              controller: fake,
              ready: Promise.resolve(dummyReg),
              register: function () { return Promise.resolve(dummyReg); },
              getRegistration: function () { return Promise.resolve(dummyReg); },
              getRegistrations: function () { return Promise.resolve([dummyReg]); },
              addEventListener: function () {},
              removeEventListener: function () {},
              startMessages: function () {}
            };
            try {
              Object.defineProperty(navigator, 'serviceWorker', {
                configurable: true,
                enumerable: true,
                value: swShim
              });
            } catch (replaceErr) {
              var sw = navigator.serviceWorker;
              if (sw) {
                try { sw.register = function () { return Promise.resolve(dummyReg); }; } catch (e) {}
                try { Object.defineProperty(sw, 'ready', { configurable: true, get: function () { return Promise.resolve(dummyReg); } }); } catch (e) {}
                try { Object.defineProperty(sw, 'controller', { configurable: true, get: function () { return fake; } }); } catch (e) {}
              }
            }
          } catch (e) {}
        })();
        """
    }

    private static func jsString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}

func nativeRoute(for url: URL, deviceId: String) -> AppRoute? {
    let path = url.path
    let parts = path.split(separator: "/").map(String.init)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    let workspaceId = query?.first(where: { $0.name == "workspaceId" })?.value
    func device(_ fallbackIndex: Int) -> String {
        if parts.count > fallbackIndex, parts[0] == "devices" { return parts[1] }
        return deviceId
    }
    if parts.last == "new" && parts.contains("threads") {
        return .threadNew(deviceId: device(1), workspaceId: workspaceId)
    }
    if parts.last == "import" && parts.contains("threads") {
        return .threadImport(deviceId: device(1))
    }
    if let threadIndex = parts.firstIndex(of: "threads"), threadIndex + 1 < parts.count {
        let threadId = parts[threadIndex + 1]
        if threadId != "new" && threadId != "import" {
            return .threadDetail(deviceId: device(1), threadId: threadId, workspaceId: workspaceId)
        }
    }
    if parts.last == "threads" {
        if let workspaceId { return .threads(deviceId: device(1), workspaceId: workspaceId) }
        return .workspaces(deviceId: device(1))
    }
    if parts.last == "workspaces" || (parts.contains("workspaces") && parts.last == "new") {
        if parts.last == "new" { return .workspaceNew(deviceId: device(1)) }
        return .workspaces(deviceId: device(1))
    }
    if path == "/relay-devices" { return .devices }
    if path == "/relay-account" { return .account }
    if path == "/relay-settings" { return .settings }
    if path == "/" || path == "/relay-portal" { return .home }
    return nil
}
