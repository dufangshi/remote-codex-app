import AppKit
import UserNotifications
import RemoteCodexCore

@MainActor
final class SystemNotifications {
    weak var state: AppState?
    private var task: Task<Void, Never>?
    private weak var client: RelayClient?
    private var cursor = NotificationCursor()
    private var epoch = UUID()
    private var allowed = false

    func start(state: AppState, client: RelayClient) {
        guard self.client !== client else { return }
        stop(); self.state = state; self.client = client
        let epoch = epoch
        task = Task { [weak self] in
            guard let self else { return }
            if let initial: WorkbenchSnapshot = try? await client.relay("/relay/account/workbench") { _ = cursor.pending(initial.notifications) }
            await enable()
            while !Task.isCancelled, self.epoch == epoch, state.client === client {
                do {
                    let snapshot: WorkbenchSnapshot = try await client.relay("/relay/account/workbench")
                    guard self.epoch == epoch, state.client === client, !Task.isCancelled else { return }
                    state.navigation = snapshot
                    for event in cursor.pending(snapshot.notifications) {
                        guard allowed else { cursor.acknowledge(event.id); continue }
                        guard NotificationCursor.destination(event.href, origin: client.origin) != nil else { cursor.acknowledge(event.id); continue }
                        let content = UNMutableNotificationContent()
                        content.title = "Remote Codex"
                        // Never put conversation text or titles on the lock screen.
                        content.body = event.title.hasSuffix("failed") ? "A thread turn failed. Click to view." : "A thread turn completed. Click to view."
                        content.sound = .default
                        content.userInfo = ["origin": client.origin.absoluteString, "session": client.notificationScope, "href": event.href]
                        let request = UNNotificationRequest(identifier: client.notificationScope + ":" + event.id, content: content, trigger: nil)
                        try await UNUserNotificationCenter.current().add(request)
                        cursor.acknowledge(event.id)
                    }
                } catch {
                    if !Task.isCancelled { state.notificationStatus = "Notification monitoring will retry: " + error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    func enable() async {
        do {
            allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            state?.notificationStatus = allowed ? "macOS notifications enabled · monitoring while app is running" : "Notifications blocked. Allow Remote Codex in System Settings → Notifications."
        } catch { state?.notificationStatus = error.localizedDescription }
    }
    func stop() {
        task?.cancel(); task = nil; client = nil; epoch = UUID(); cursor = NotificationCursor()
    }
    func open(_ info: [AnyHashable: Any]) {
        guard let state, let client = state.client, state.authenticated,
              info["origin"] as? String == client.origin.absoluteString,
              info["session"] as? String == client.notificationScope,
              let href = info["href"] as? String,
              let target = NotificationCursor.destination(href, origin: client.origin) else { return }
        state.selectReference(target.device, target.thread)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.makeKeyAndOrderFront(nil)
    }
}
