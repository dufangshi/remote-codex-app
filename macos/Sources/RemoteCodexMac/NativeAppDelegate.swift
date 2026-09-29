import AppKit
import UserNotifications

@MainActor
final class NativeAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var state: AppState?
    private var pendingNotification: [AnyHashable: Any]?
    func restoreNotification() {
        guard let info = pendingNotification, state?.authenticated == true else { return }
        pendingNotification = nil; state?.systemNotifications.open(info)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            if self.state?.authenticated == true { self.state?.systemNotifications.open(info) }
            else { self.pendingNotification = info }
            completionHandler()
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state?.hasUnsavedFiles == true || state?.hasDrafts == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Remote Codex?"
        alert.informativeText = "Save any edited files and drafts before quitting. Sent conversations remain on your device, and running agents continue in the background."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
