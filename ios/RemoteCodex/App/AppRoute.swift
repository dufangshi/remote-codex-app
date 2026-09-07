import Foundation

enum AppRoute: Equatable, Hashable {
    case connect
    case home
    case guide
    case portal
    case devices
    case account
    case settings
    case workspaces(deviceId: String)
    case workspaceNew(deviceId: String)
    case threads(deviceId: String, workspaceId: String)
    case threadNew(deviceId: String, workspaceId: String?)
    case threadImport(deviceId: String)
    case threadDetail(deviceId: String, threadId: String, workspaceId: String?)

    var deviceId: String? {
        switch self {
        case .workspaces(let id), .workspaceNew(let id), .threads(let id, _),
             .threadNew(let id, _), .threadImport(let id), .threadDetail(let id, _, _):
            return id
        default:
            return nil
        }
    }
}

final class NavController: ObservableObject {
    @Published private(set) var stack: [AppRoute]
    @Published private(set) var current: AppRoute

    init(_ initial: AppRoute) {
        stack = [initial]
        current = initial
    }

    func push(_ route: AppRoute) {
        if stack.last == route { return }
        stack.append(route)
        current = route
    }

    func replace(_ route: AppRoute) {
        if !stack.isEmpty { stack.removeLast() }
        stack.append(route)
        current = route
    }

    func reset(_ route: AppRoute) {
        stack = [route]
        current = route
    }

    var canSwipeBack: Bool { stack.count > 1 }

    var previous: AppRoute? {
        stack.count >= 2 ? stack[stack.count - 2] : nil
    }

    func pop() {
        if stack.count > 1 { stack.removeLast() }
        current = stack.last ?? .connect
    }

    func back() {
        if stack.count > 1 {
            stack.removeLast()
            current = stack.last ?? .connect
            return
        }
        if let fallback = fallback(from: current) {
            stack = [fallback]
            current = fallback
        }
    }

    func fallback(from route: AppRoute) -> AppRoute? {
        switch route {
        case .threadDetail(let deviceId, _, let workspaceId):
            if let workspaceId, !workspaceId.isEmpty {
                return .threads(deviceId: deviceId, workspaceId: workspaceId)
            }
            return .workspaces(deviceId: deviceId)
        case .threadNew(let deviceId, let workspaceId):
            if let workspaceId, !workspaceId.isEmpty {
                return .threads(deviceId: deviceId, workspaceId: workspaceId)
            }
            return .workspaces(deviceId: deviceId)
        case .threadImport(let deviceId):
            return .workspaces(deviceId: deviceId)
        case .threads(let deviceId, _):
            return .workspaces(deviceId: deviceId)
        case .workspaceNew(let deviceId):
            return .workspaces(deviceId: deviceId)
        case .workspaces:
            return .devices
        case .account, .devices, .guide, .portal, .settings:
            return .home
        case .home:
            return .connect
        case .connect:
            return nil
        }
    }
}
