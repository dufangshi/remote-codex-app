import SwiftUI
import UserNotifications
import WebKit
import BackgroundTasks

@main
struct RemoteCodexApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(store: model.store, nav: model.nav, api: model.api)
                .onOpenURL { url in
                    model.apply(url: url)
                }
                .onAppear {
                    NotificationDelegate.shared.onOpen = { deviceId, threadId in
                        model.store.deviceId = deviceId
                        model.nav.push(.threadDetail(deviceId: deviceId, threadId: threadId, workspaceId: nil))
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            EventWatcher.shared.isForeground = phase == .active
            if phase == .active, model.store.isSignedIn {
                EventWatcher.shared.start()
            }
            if phase == .background {
                EventWatcher.shared.scheduleBackgroundRefresh()
            }
        }
    }
}

final class AppModel: ObservableObject {
    let store: SessionStore
    let nav: NavController
    let api: APIClient

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let defaults = UserDefaults.standard
            defaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.remotecodex.app")
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            URLCache.shared.removeAllCachedResponses()
            WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast,
                completionHandler: {}
            )
        }
        let store = SessionStore()
        self.store = store
        self.nav = NavController(store.hasRelayUrl ? .home : .connect)
        self.api = APIClient(store: store)
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        EventWatcher.shared.registerBackgroundTasks()
        EventWatcher.shared.store = store
        if store.isSignedIn {
            EventWatcher.shared.start()
        }
    }

    func apply(url: URL) {
        if let route = nativeRoute(for: url, deviceId: store.deviceId) {
            if case .threadDetail(let deviceId, _, _) = route {
                store.deviceId = deviceId
            }
            nav.push(route)
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    var onOpen: ((String, String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return []
        }
        return [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let deviceId = info["deviceId"] as? String, let threadId = info["threadId"] as? String {
            await MainActor.run { onOpen?(deviceId, threadId) }
        }
    }
}
