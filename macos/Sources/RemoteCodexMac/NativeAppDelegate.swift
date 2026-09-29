import AppKit

@MainActor
final class NativeAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state?.hasUnsavedFiles == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "You have unsaved workspace files"
        alert.informativeText = "Cancel to save your drafts. Quitting now discards the unsaved edits; remote files are not changed."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Without Saving")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
