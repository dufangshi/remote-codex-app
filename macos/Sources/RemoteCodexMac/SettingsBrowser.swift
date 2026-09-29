import SwiftUI
import WebKit
import RemoteCodexCore

/// Web reuse is scoped to the Settings sheet; conversation and file UI stay native.
@MainActor
final class SettingsBrowser: ObservableObject {
    @Published var loading = true
    @Published var error: String?
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var web: WKWebView?
    @Published var themeMode = "system"
    @Published var closed = false
    var action = "Open settings"
    var colorScheme: ColorScheme? { themeMode == "light" ? .light : themeMode == "dark" ? .dark : nil }
    var coordinator: SettingsWebView.Coordinator?
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
    static let preferenceKeys: Set<String> = ["remote-codex-theme-mode", "remote-codex-font-size", "remote-codex-default-backend", "remote-codex-auto-collapse-completed-turns", "remote-codex-show-reasoning-summaries", "remote-codex.explorer-width"]

    func reset() {
        web?.stopLoading(); web = nil; coordinator = nil; client = nil
        origin = nil; startURL = nil; url = nil; cookies = []; initialPins = [:]; initialPreferences = [:]
        previousProfile = nil; error = nil; loading = true; canGoBack = false; canGoForward = false
    }

    func start(_ client: RelayClient, devices: [Device], path: String = "/relay-devices") async {
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
            initialPreferences["remote-codex-theme-mode"] = UserDefaults.standard.string(forKey: "appearance") ?? "system"
            initialPreferences["remote-codex-font-size"] = String(UserDefaults.standard.integer(forKey: "native-font-size").clampedFontSize)
            startURL = URL(string: client.origin.absoluteString + path)
        } catch { self.error = error.localizedDescription; loading = false }
    }
    func remember(_ location: URL) {
        guard let origin, BrowserPolicy.sameOrigin(location, origin) else { return }
        url = location
        if let path = BrowserPolicy.rememberedPath(location, origin: origin) { UserDefaults.standard.set(path, forKey: "workspace-route:" + origin.absoluteString) }
    }
    func persistPreferences(_ preferences: [String: String]) {
            themeMode = preferences["remote-codex-theme-mode"] ?? "system"; UserDefaults.standard.set(themeMode, forKey: "appearance")
            if let size = preferences["remote-codex-font-size"].flatMap(Int.init) { UserDefaults.standard.set(size.clampedFontSize, forKey: "native-font-size") }
            if let collapse = preferences["remote-codex-auto-collapse-completed-turns"] { UserDefaults.standard.set(collapse == "true", forKey: "native-auto-collapse") }
            if let summaries = preferences["remote-codex-show-reasoning-summaries"] { UserDefaults.standard.set(summaries == "true", forKey: "native-reasoning-summaries") }
    }
    func persistProfile(_ profile: [String: Any]) async {
        if let preferences = profile["preferences"] as? [String: String] { persistPreferences(preferences) }
        guard !savingProfile, !profileKey.isEmpty else { return }
        savingProfile = true; defer { savingProfile = false }
        do {
            let data = try JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
            guard data.count < 2_000_000, let text = String(data: data, encoding: .utf8), text != previousProfile else { return }
            try await vault.write(text, for: profileKey)
            previousProfile = text
        } catch { self.error = "Could not preserve workspace preferences and device pins: \(error.localizedDescription)" }
    }

}

struct SharedSettingsView: View {
    var action = "Open settings"
    var close: () -> Void
    @EnvironmentObject var state: AppState
    @StateObject private var browser = SettingsBrowser()
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
                SettingsWebView(url: url, cookies: browser.cookies, reportError: { browser.error = $0 }, browser: browser)
            } else if browser.loading {
                VStack(spacing: 16) { ProgressView("Opening settings…"); Button("Cancel", action: close) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Workspace unavailable", systemImage: "network", description: Text("Review the connection error above.")); Button("Close", action: close)
            }
        }
        .overlay(alignment: .top) { if browser.loading { ProgressView().progressViewStyle(.linear).frame(height: 2) } }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.25))
        .onExitCommand(perform: close)
        .task {
            browser.action = action
            if let client = state.client {
                let path: String
                if let device = state.deviceID, let thread = state.threadID { path = "/devices/\(device)/threads/\(thread)" }
                else if let device = state.deviceID { path = "/devices/\(device)/workspaces" }
                else { path = "/relay-devices" }
                await browser.start(client, devices: state.devices, path: path)
            }
        }
        .onChange(of: browser.closed) { _, closed in if closed { close() } }
        .onDisappear { Task { if state.client?.signedIn == false { await state.signOut() }; await state.refreshLists(); await state.refreshThread() } }
    }
}
