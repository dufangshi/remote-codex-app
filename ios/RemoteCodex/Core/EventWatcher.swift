import Foundation
import UIKit
import UserNotifications

final class EventWatcher: NSObject, URLSessionWebSocketDelegate {
    static let shared = EventWatcher()

    var store: SessionStore?
    var isForeground = true
    var openThread: (deviceId: String, threadId: String)?
    var onBanner: ((String, String, String, String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var running = false
    private var titles: [String: String] = [:]
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func start() {
        running = true
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "agent-watch") { [weak self] in
                if let id = self?.backgroundTask, id != .invalid {
                    UIApplication.shared.endBackgroundTask(id)
                    self?.backgroundTask = .invalid
                }
            }
        }
        connect()
        startPolling()
    }

    func stop() {
        running = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func refresh() {
        running = true
        task?.cancel(with: .goingAway, reason: nil)
        connect()
        startPolling()
        Task { @MainActor in
            await pollOnce()
        }
    }

    func requestPermission() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private var knownStatus: [String: String] = [:]
    private var notified: Set<String> = []
    private var primed = false
    private var polling = false

    private func startPolling() {
        guard !polling else { return }
        polling = true
        Task { @MainActor [weak self] in
            while let self, self.running {
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self?.polling = false
        }
    }

    private func pollOnce() async {
        guard let store, !store.deviceId.isEmpty, !store.token.isEmpty else { return }
        let api = APIClient(store: store)
        let threads: [ThreadSummary]
        do {
            threads = try await api.fetchThreads(deviceId: store.deviceId)
        } catch {
            NSLog("E2E_POLL fetch failed %@", error.localizedDescription)
            return
        }
        NSLog("E2E_POLL device=%@ threads=%d primed=%d", store.deviceId, threads.count, primed ? 1 : 0)
        if !primed {
            for thread in threads {
                knownStatus[thread.id] = thread.status ?? "idle"
                notified.insert(thread.id)
            }
            primed = true
            return
        }
        for thread in threads {
            let status = thread.status ?? "idle"
            let previous = knownStatus[thread.id]
            knownStatus[thread.id] = status
            titles[thread.id] = thread.title ?? titles[thread.id] ?? "Thread"
            let finished = ["idle", "failed", "interrupted", "system_error"].contains(status)
            let wasRunning = previous == "running"
            if finished && !notified.contains(thread.id) && (wasRunning || previous == nil) {
                notified.insert(thread.id)
                notify(
                    deviceId: store.deviceId,
                    threadId: thread.id,
                    title: thread.title ?? "Thread",
                    body: status == "failed" ? "Agent run failed." : "Agent run finished."
                )
            }
        }
    }

    private func isRecent(_ value: String?) -> Bool {
        guard let value, let date = ISO8601DateFormatter().date(from: value) ?? ISO8601DateFormatter.full.date(from: value) else {
            return false
        }
        return Date().timeIntervalSince(date) < 30
    }

    private func connect() {
        guard running, let store, !store.deviceId.isEmpty, !store.token.isEmpty, !store.relayUrl.isEmpty else { return }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.webSocketTask(with: APIClient(store: store).socketURL(deviceId: store.deviceId))
        self.task = task
        task.resume()
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                if self.running {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.connect() }
                }
            case .success(let message):
                if case .string(let text) = message {
                    self.handle(text)
                }
                self.listen()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ThreadEvent.self, from: data)
        else { return }
        if event.type == "thread.updated", let title = event.payload?["title"]?.string {
            titles[event.threadId] = title
        }
        let status = event.payload?["status"]?.string
        let completed = event.type == "thread.turn.completed"
            || event.type == "thread.turn.failed"
            || (event.type == "thread.updated" && ["idle", "failed", "interrupted", "system_error"].contains(status ?? ""))
        guard completed else { return }
        if isForeground,
           openThread?.threadId == event.threadId,
           openThread?.deviceId == store?.deviceId {
            return
        }
        let failed = event.type == "thread.turn.failed" || status == "failed"
        let title = titles[event.threadId] ?? "Thread"
        let body = failed ? (event.payload?["error"]?.string ?? "Agent run failed.") : "Agent run finished."
        notify(deviceId: store?.deviceId ?? "", threadId: event.threadId, title: title, body: body)
    }

    private func notify(deviceId: String, threadId: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deviceId": deviceId, "threadId": threadId]
        content.threadIdentifier = threadId
        let request = UNNotificationRequest(identifier: threadId, content: content, trigger: nil)
        if !ProcessInfo.processInfo.arguments.contains("--uitesting") {
            UNUserNotificationCenter.current().add(request)
        }
        DispatchQueue.main.async {
            self.onBanner?(deviceId, threadId, title, body)
            NotificationCenter.default.post(
                name: .agentRunFinished,
                object: nil,
                userInfo: ["deviceId": deviceId, "threadId": threadId, "title": title, "body": body]
            )
        }
    }
}

extension Notification.Name {
    static let agentRunFinished = Notification.Name("remoteCodex.agentRunFinished")
}

private extension ISO8601DateFormatter {
    static let full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
