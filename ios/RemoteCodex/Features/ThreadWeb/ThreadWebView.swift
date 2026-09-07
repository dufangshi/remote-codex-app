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
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
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

struct ThreadWebView: UIViewControllerRepresentable {
    let store: SessionStore
    let deviceId: String
    let threadId: String
    let themeMode: ThemeMode
    let onLeave: (AppRoute) -> Void

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
        controller.load(store: store, deviceId: deviceId, threadId: threadId, themeMode: themeMode)
    }
}

final class ThreadWebController: UIViewController, WKNavigationDelegate {
    let accessibilityProbe = UILabel()
    private var webView: WKWebView?
    var deviceId = ""
    var threadId = ""
    var onLeave: ((AppRoute) -> Void)?
    private var loadedKey = ""
    private var interceptLeaves = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityIdentifier = "threadScreen"
        accessibilityProbe.text = "Thread"
        accessibilityProbe.font = .systemFont(ofSize: 11, weight: .semibold)
        accessibilityProbe.textAlignment = .center
        accessibilityProbe.isAccessibilityElement = true
        accessibilityProbe.accessibilityIdentifier = "threadWebView"
        accessibilityProbe.accessibilityLabel = "Thread"
        accessibilityProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accessibilityProbe)
        NSLayoutConstraint.activate([
            accessibilityProbe.topAnchor.constraint(equalTo: view.topAnchor),
            accessibilityProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accessibilityProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accessibilityProbe.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    func load(store: SessionStore, deviceId: String, threadId: String, themeMode: ThemeMode) {
        self.deviceId = deviceId
        self.threadId = threadId
        let key = "\(deviceId)|\(threadId)|\(store.relayUrl)"
        guard key != loadedKey else { return }
        loadedKey = key

        let script = WKUserScript(source: Self.injectionJS(store: store, deviceId: deviceId, themeMode: themeMode), injectionTime: .atDocumentStart, forMainFrameOnly: false)
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
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.accessibilityIdentifier = "threadWebView"
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: accessibilityProbe.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        webView = web

        let origin = store.relayUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = "\(origin)/devices/\(enc(deviceId))/threads/\(enc(threadId))?nativeApp=1"
        let html = """
        <!doctype html>
        <meta charset="utf-8">
        <title>Thread</title>
        <body>Thread</body>
        <script>
        \(Self.injectionJS(store: store, deviceId: deviceId, themeMode: themeMode))
        try { location.replace(\(Self.jsString(target))); } catch (e) {}
        </script>
        """
        DispatchQueue.main.async { [weak web] in
            web?.loadHTMLString(html, baseURL: URL(string: origin + "/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.path.contains("/threads/") == true {
            interceptLeaves = true
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard interceptLeaves, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "about" || url.path.isEmpty || url.path == "/" {
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

    private static func injectionJS(store: SessionStore, deviceId: String, themeMode: ThemeMode) -> String {
        """
        try {
          localStorage.setItem('remote-codex-relay-mode', 'true');
          localStorage.setItem('remote-codex-relay-token', \(jsString(store.token)));
          localStorage.setItem('remote-codex-relay-device-id', \(jsString(deviceId)));
          localStorage.setItem('remote-codex-theme-mode', \(jsString(themeMode.rawValue)));
          localStorage.setItem('remote-codex-auto-collapse-completed-turns', \(jsString(store.autoCollapseCompletedTurns ? "true" : "false")));
        } catch (e) {}
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
    if path == "/" || path == "/relay-portal" { return .home }
    return nil
}
