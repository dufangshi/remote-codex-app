import Foundation

final class SessionStore: ObservableObject {
    @Published var relayUrl: String {
        didSet { defaults.set(relayUrl, forKey: Keys.url) }
    }
    @Published var token: String {
        didSet { defaults.set(token, forKey: Keys.token) }
    }
    @Published var deviceId: String {
        didSet { defaults.set(deviceId, forKey: Keys.device) }
    }
    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: Keys.theme) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.relayUrl = defaults.string(forKey: Keys.url) ?? ""
        self.token = defaults.string(forKey: Keys.token) ?? ""
        self.deviceId = defaults.string(forKey: Keys.device) ?? ""
        self.themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.theme) ?? "system") ?? .system
    }

    var hasRelayUrl: Bool { !relayUrl.isEmpty }
    var isSignedIn: Bool { !token.isEmpty }

    func clearSession() {
        token = ""
        deviceId = ""
    }

    private enum Keys {
        static let url = "relay_url"
        static let token = "relay_token"
        static let device = "relay_device_id"
        static let theme = "theme_mode"
    }
}
