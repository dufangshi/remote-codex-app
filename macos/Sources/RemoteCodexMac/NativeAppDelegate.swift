import AppKit

@MainActor
final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    weak var browser: WorkspaceBrowser?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state?.hasUnsavedFiles == true || browser?.web != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Remote Codex?"
        alert.informativeText = "Save any edited files and drafts before quitting. Sent conversations remain on your device, and running agents continue in the background."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
