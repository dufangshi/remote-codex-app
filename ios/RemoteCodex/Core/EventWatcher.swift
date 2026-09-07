import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

final class EventWatcher: NSObject, URLSessionWebSocketDelegate {
    static let shared = EventWatcher()
    static let backgroundTaskId = "com.remotecodex.app.watch"

    var store: SessionStore?
    var isForeground = true
    var openThread: (deviceId: String, threadId: String)?
    var onBanner: ((String, String, String, String) -> Void)?

    private var session: URLSession?
    private var sockets: [String: URLSessionWebSocketTask] = [:]
    private var running = false
    private var polling = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private let state = WatchState()

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskId, using: nil) { [weak self] task in
            self?.handleBackground(task as? BGAppRefreshTask)
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func start() {
        running = true
        extendBackgroundExecution()
        if session == nil {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        startPolling()
        Task { await self.tick() }
    }

    func stop() {
        running = false
        closeSockets()
        endBackgroundExecution()
        Task { await state.reset() }
    }

    func refresh() {
        guard store?.isSignedIn == true else { return }
        running = true
        startPolling()
        Task { await self.tick() }
    }

    func requestPermission() {
        if ProcessInfo.processInfo.arguments.contains("--uitesting") { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func handleBackground(_ task: BGAppRefreshTask?) {
        scheduleBackgroundRefresh()
        let work = Task { await self.tick() }
        task?.expirationHandler = { work.cancel() }
        Task {
            _ = await work.result
            task?.setTaskCompleted(success: true)
        }
    }

    private func startPolling() {
        guard !polling else { return }
        polling = true
        Task { [weak self] in
            while let self, self.running {
                await self.tick()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
            self?.polling = false
        }
    }

    private func tick() async {
        guard let store, store.isSignedIn, !store.token.isEmpty, !store.relayUrl.isEmpty else { return }
        let api = APIClient(store: store)
        let deviceIds = await loadDeviceIds(api: api)
        await pollDevices(api: api, deviceIds: deviceIds)
        await MainActor.run { self.syncSockets(deviceIds: deviceIds, store: store) }
    }

    private func loadDeviceIds(api: APIClient) async -> [String] {
        guard let portal = try? await api.fetchPortal() else { return [] }
        var ids: [String] = []
        var names: [String: String] = [:]
        for device in portal.devices {
            ids.append(device.id)
            names[device.id] = device.name
        }
        for grant in portal.sharedDevicesWithMe ?? [] where !ids.contains(grant.deviceId) {
            ids.append(grant.deviceId)
            names[grant.deviceId] = grant.deviceName ?? grant.deviceId
        }
        await state.mergeNames(names)
        return ids
    }

    private func pollDevices(api: APIClient, deviceIds: [String]) async {
        for deviceId in deviceIds {
            let threads: [ThreadSummary]
            do {
                threads = try await api.fetchThreads(deviceId: deviceId)
            } catch {
                continue
            }
            if await state.primeIfNeeded(deviceId, threads: threads) {
                continue
            }
            for thread in threads {
                if let pending = await state.consider(
                    deviceId: deviceId,
                    threadId: thread.id,
                    status: thread.status,
                    title: thread.title,
                    completedAt: thread.lastTurnCompletedAt ?? thread.updatedAt,
                    eventType: nil
                ) {
                    emit(pending)
                }
            }
        }
    }

    private func syncSockets(deviceIds: [String], store: SessionStore) {
        let wanted = Set(deviceIds)
        for (id, task) in sockets where !wanted.contains(id) {
            task.cancel(with: .goingAway, reason: nil)
            sockets[id] = nil
        }
        sockets = sockets.filter { wanted.contains($0.key) }
        for deviceId in deviceIds where sockets[deviceId] == nil {
            connect(deviceId: deviceId, store: store)
        }
    }

    private func connect(deviceId: String, store: SessionStore) {
        guard running, let session else { return }
        let task = session.webSocketTask(with: APIClient(store: store).socketURL(deviceId: deviceId))
        sockets[deviceId] = task
        task.resume()
        listen(deviceId: deviceId, task: task)
    }

    private func listen(deviceId: String, task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                if self.sockets[deviceId] === task {
                    self.sockets[deviceId] = nil
                }
                if self.running {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        guard let store = self.store, self.sockets[deviceId] == nil else { return }
                        self.connect(deviceId: deviceId, store: store)
                    }
                }
            case .success(let message):
                if case .string(let text) = message {
                    self.handle(deviceId: deviceId, text: text)
                }
                if self.sockets[deviceId] === task {
                    self.listen(deviceId: deviceId, task: task)
                }
            }
        }
    }

    private func handle(deviceId: String, text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ThreadEvent.self, from: data)
        else { return }
        Task {
            if let pending = await self.state.consider(
                deviceId: deviceId,
                threadId: event.threadId,
                status: event.payload?["status"]?.string,
                title: event.payload?["title"]?.string,
                completedAt: nil,
                eventType: event.type
            ) {
                self.emit(pending)
            }
        }
    }

    private func emit(_ pending: PendingNotify) {
        if isForeground,
           openThread?.threadId == pending.threadId,
           openThread?.deviceId == pending.deviceId {
            return
        }
        notify(
            deviceId: pending.deviceId,
            threadId: pending.threadId,
            title: pending.title,
            body: pending.body
        )
    }

    func isRecent(_ value: String?) -> Bool {
        WatchState.isRecent(value)
    }

    private func notify(deviceId: String, threadId: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["deviceId": deviceId, "threadId": threadId]
        content.threadIdentifier = "\(deviceId):\(threadId)"
        let request = UNNotificationRequest(
            identifier: "\(deviceId):\(threadId):\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
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

    private func closeSockets() {
        for task in sockets.values {
            task.cancel(with: .goingAway, reason: nil)
        }
        sockets.removeAll()
    }

    private func extendBackgroundExecution() {
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "agent-watch") { [weak self] in
                self?.endBackgroundExecution()
            }
        }
    }

    private func endBackgroundExecution() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

private struct PendingNotify {
    let deviceId: String
    let threadId: String
    let title: String
    let body: String
}

private actor WatchState {
    private var knownStatus: [String: String] = [:]
    private var recentlyNotified: [String: Date] = [:]
    private var primedDevices: Set<String> = []
    private var titles: [String: String] = [:]
    private var deviceNames: [String: String] = [:]

    func reset() {
        knownStatus.removeAll()
        recentlyNotified.removeAll()
        primedDevices.removeAll()
        titles.removeAll()
        deviceNames.removeAll()
    }

    func mergeNames(_ names: [String: String]) {
        deviceNames.merge(names) { _, new in new }
    }

    func primeIfNeeded(_ deviceId: String, threads: [ThreadSummary]) -> Bool {
        guard primedDevices.insert(deviceId).inserted else { return false }
        for thread in threads {
            let key = Self.key(deviceId, thread.id)
            knownStatus[key] = thread.status ?? "idle"
            if let title = thread.title { titles[key] = title }
        }
        return true
    }

    func consider(
        deviceId: String,
        threadId: String,
        status: String?,
        title: String?,
        completedAt: String?,
        eventType: String?
    ) -> PendingNotify? {
        let key = Self.key(deviceId, threadId)
        let turnDone = eventType == "thread.turn.completed" || eventType == "thread.turn.failed"
        let failed = eventType == "thread.turn.failed" || status == "failed"
        let finishedStatuses: Set<String> = ["idle", "failed", "interrupted", "system_error"]
        if let title, !title.isEmpty { titles[key] = title }
        let previous = knownStatus[key]
        if status == "running" {
            knownStatus[key] = "running"
            return nil
        }
        let finished = turnDone || finishedStatuses.contains(status ?? "")
        if !finished {
            if let status { knownStatus[key] = status }
            return nil
        }
        knownStatus[key] = failed ? "failed" : (status.flatMap { finishedStatuses.contains($0) ? $0 : nil } ?? "idle")
        let wasRunning = previous == "running"
        let appearedFinished = previous == nil && eventType == nil && Self.isRecent(completedAt)
        guard turnDone || wasRunning || appearedFinished else { return nil }
        if let last = recentlyNotified[key], Date().timeIntervalSince(last) < 10 {
            return nil
        }
        recentlyNotified[key] = Date()
        let deviceName = deviceNames[deviceId]
        let prefix = deviceName.flatMap { $0.isEmpty ? nil : "\($0) · " } ?? ""
        return PendingNotify(
            deviceId: deviceId,
            threadId: threadId,
            title: titles[key] ?? "Thread",
            body: failed ? "\(prefix)Agent run failed." : "\(prefix)Agent run finished."
        )
    }

    static func isRecent(_ value: String?) -> Bool {
        guard let value, let date = ISO8601DateFormatter().date(from: value) ?? ISO8601DateFormatter.full.date(from: value) else {
            return false
        }
        return Date().timeIntervalSince(date) < 30
    }

    private static func key(_ deviceId: String, _ threadId: String) -> String {
        "\(deviceId)/\(threadId)"
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
