import SwiftUI
import WebKit
import RemoteCodexCore

/// One long-lived WebKit workspace, not a web page nested inside another workspace.
@MainActor
final class WorkspaceBrowser: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var web: WKWebView?
    @Published var themeMode = "system"
    var colorScheme: ColorScheme? { themeMode == "light" ? .light : themeMode == "dark" ? .dark : nil }
    var coordinator: FullWorkspaceView.Coordinator?
    private var vault: SecretStore = KeychainStore(service: Bundle.main.bundleIdentifier ?? "com.remotecodex.mac")
    private var profileKey = ""
    private var previousProfile: String?
    private var savingProfile = false
    var origin: URL?
    var initialPins: [String: String] = [:]
    var initialPreferences: [String: String] = [:]
    @Published var startURL: URL?
    var cookies: [HTTPCookie] = []
    var client: RelayClient?
    static let preferenceKeys: Set<String> = ["remote-codex-theme-mode", "remote-codex-default-backend", "remote-codex-auto-collapse-completed-turns", "remote-codex-show-reasoning-summaries", "remote-codex.explorer-width"]

    func reset() {
        web?.stopLoading(); web = nil; coordinator = nil; client = nil
        origin = nil; startURL = nil; url = nil; cookies = []; initialPins = [:]; initialPreferences = [:]
        previousProfile = nil; error = nil; loading = true; canGoBack = false; canGoForward = false
    }

    func start(_ client: RelayClient, devices: [Device]) async {
        guard origin == nil else { return }
        self.client = client
        origin = client.origin
        profileKey = "web-profile:" + client.origin.absoluteString
        do {
            if let saved = try await vault.read(profileKey), let bytes = saved.data(using: .utf8),
               let profile = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                initialPins = profile["pins"] as? [String: String] ?? [:]
                initialPreferences = (profile["preferences"] as? [String: String] ?? [:]).filter { Self.preferenceKeys.contains($0.key) }
                previousProfile = saved
                themeMode = initialPreferences["remote-codex-theme-mode"] ?? "system"
            }
            // Migrate existing native trust decisions before any web device request.
            let nativePins = try await client.pinnedIdentities(devices.map(\.id))
            for (id, pin) in nativePins {
                if let prior = initialPins[id], prior != pin { throw APIError("Native and web device identity pins disagree. Verify this device before reconnecting.") }
                initialPins[id] = pin
            }
            cookies = client.browserCookies()
            startURL = BrowserPolicy.restoredURL(UserDefaults.standard.string(forKey: "workspace-route:" + client.origin.absoluteString), origin: client.origin)
        } catch { self.error = error.localizedDescription; loading = false }
    }
    func remember(_ location: URL) {
        guard let origin, BrowserPolicy.sameOrigin(location, origin) else { return }
        url = location
        if let path = BrowserPolicy.rememberedPath(location, origin: origin) { UserDefaults.standard.set(path, forKey: "workspace-route:" + origin.absoluteString) }
    }
    func persistProfile(_ profile: [String: Any]) async {
        if let preferences = profile["preferences"] as? [String: String] { themeMode = preferences["remote-codex-theme-mode"] ?? "system" }
        guard !savingProfile, !profileKey.isEmpty else { return }
        savingProfile = true; defer { savingProfile = false }
        do {
            let data = try JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
            guard data.count < 2_000_000, let text = String(data: data, encoding: .utf8), text != previousProfile else { return }
            try await vault.write(text, for: profileKey)
            previousProfile = text
        } catch { self.error = "Could not preserve workspace preferences and device pins: \(error.localizedDescription)" }
    }
    func perform(_ action: String) {
        guard let web else { return }
        switch action {
        case "back": web.goBack()
        case "forward": web.goForward()
        case "reload":
            let alert = NSAlert(); alert.messageText = "Reload workspace?"
            alert.informativeText = "Save any edited files first. Sent messages are already stored on the device."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Reload")
            if alert.runModal() == .alertSecondButtonReturn { web.reload() }
        case "home": if let origin { web.load(URLRequest(url: origin.appendingPathComponent("relay-devices"))) }
        case "zoomIn": web.pageZoom = min(2, web.pageZoom + 0.1)
        case "zoomOut": web.pageZoom = max(0.6, web.pageZoom - 0.1)
        case "actualSize": web.pageZoom = 1
        case "settings", "newThread":
            let label = action == "settings" ? "Open settings" : "New Chat"
            Task {
                do {
                    let found = try await web.callAsyncJavaScript("const e = document.querySelector('[aria-label=\"' + label + '\"]') || [...document.querySelectorAll('button')].find(e => e.textContent.trim() === label); if(e) e.click(); return !!e;", arguments: ["label": label], in: nil, contentWorld: .page)
                    if found as? Bool != true { error = "Open a conversation to use this command." }
                } catch { self.error = error.localizedDescription }
            }
        default: break
        }
    }
    func openInBrowser() { if let url { NSWorkspace.shared.open(url) } }
}

struct DesktopWorkspaceView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var browser: WorkspaceBrowser
    var body: some View {
        VStack(spacing: 0) {
            if let message = browser.error {
                HStack {
                    InlineError(message: message) { browser.error = nil }
                    Button("Retry") {
                        if let web = browser.web { browser.error = nil; web.reload() }
                        else if let client = state.client {
                            browser.reset()
                            Task { await browser.start(client, devices: state.devices) }
                        }
                    }.padding(.trailing, 12)
                }
            }
            if let url = browser.startURL {
                FullWorkspaceView(url: url, cookies: browser.cookies, reportError: { browser.error = $0 }, browser: browser)
            } else if browser.loading {
                ProgressView("Connecting to your workspace…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Workspace unavailable", systemImage: "network", description: Text("Review the connection error above."))
            }
        }
        .overlay(alignment: .top) { if browser.loading { ProgressView().progressViewStyle(.linear).frame(height: 2) } }
        .task { if let client = state.client { await browser.start(client, devices: state.devices) } }
    }
}
