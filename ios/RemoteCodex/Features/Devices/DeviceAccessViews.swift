import SwiftUI

func supervisorSetup(relayUrl: String, token: String, windows: Bool) -> String {
    let ws = relayUrl.hasPrefix("https://")
        ? "wss://" + relayUrl.dropFirst("https://".count)
        : "ws://" + relayUrl.dropFirst("http://".count)
    let port = windows ? 45680 : 45679
    if windows {
        return """
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        $env:REMOTE_CODEX_RELAY_SERVER_URL='\(ws)'
        $env:REMOTE_CODEX_RELAY_AGENT_TOKEN='\(token)'
        $env:REMOTE_CODEX_RELAY_SUPERVISOR_PORT='\(port)'
        remote-codex relay-supervisor
        """
    }
    return """
    REMOTE_CODEX_RELAY_SERVER_URL=\(ws) \\
    REMOTE_CODEX_RELAY_AGENT_TOKEN=\(token) \\
    REMOTE_CODEX_RELAY_SUPERVISOR_PORT=\(port) \\
    remote-codex relay-supervisor
    """
}

func formatRelayTime(_ value: String?) -> String {
    guard let value, let date = ISO8601DateFormatter().date(from: value) ?? RFCFormatter.date(from: value) else {
        return value ?? ""
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    return formatter.string(from: date)
}

private enum RFCFormatter {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

func deviceActivityText(_ device: RelayDevice) -> String {
    if device.hostedStatus == "stopped" { return "Stopped. Connect to wake this VM." }
    if let hosted = device.hostedStatus, hosted != "online" {
        return "\(hostedStatusLabel(hosted)). The hosted supervisor is not ready yet."
    }
    if device.connected == true {
        if let connectedAt = device.connectedAt, !connectedAt.isEmpty {
            return "Online since \(formatRelayTime(connectedAt))"
        }
        return "Online. Connected time unavailable."
    }
    if let beat = device.lastHeartbeatAt, !beat.isEmpty {
        return "Last heartbeat \(formatRelayTime(beat))"
    }
    return "No heartbeat recorded."
}

func hostedStatusLabel(_ status: String) -> String {
    let spaced = status.replacingOccurrences(of: "_", with: " ")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
}

func permissionLabels(threadAccess: String?, workspaceAccess: String?, canCreate: Bool = false) -> [String] {
    var items = [threadAccess == "control" ? "Collaborator" : "View only"]
    switch workspaceAccess {
    case "write": items.append("Workspace write")
    case "read": items.append("Workspace read")
    default: items.append("No workspace")
    }
    if canCreate { items.append("Can create threads") }
    return items
}

struct DeviceRowView: View {
    let device: RelayDevice
    let relayHttps: Bool
    var copied = false
    var copyError: String? = nil
    let onConnect: () -> Void
    let onCopyUnix: () -> Void
    let onCopyWindows: () -> Void
    let onShare: () -> Void
    let onRotate: () -> Void
    let onDelete: () -> Void
    @Environment(\.rcColors) private var colors

    var body: some View {
        let hosted = device.hostedStatus
        let canConnect = device.connected == true || (hosted != nil && hosted != "stopping" && hosted != "deleting")
        let canCopy = hosted == nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(online: device.connected == true)
                Text(device.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(colors.fg)
                    .lineLimit(1)
                    .accessibilityIdentifier("device-\(device.id)")
                Spacer()
                if let hosted {
                    Text("Hosted: \(hostedStatusLabel(hosted))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.fgMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(colors.muted)
                        .clipShape(Capsule())
                }
            }
            Text(device.tokenPreview ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(colors.fgMuted)
            Text(deviceActivityText(device)).font(.system(size: 12)).foregroundStyle(colors.fgMuted)
            Text(relayHttps ? "Device connection uses HTTPS" : "Connection is not end-to-end encrypted")
                .font(.system(size: 11))
                .foregroundStyle(relayHttps ? colors.successFg : colors.fgMuted)
            if copied {
                Text("Setup command copied.").font(.system(size: 12)).foregroundStyle(colors.successFg)
            }
            if let copyError {
                Text(copyError).font(.system(size: 12)).foregroundStyle(colors.dangerFg)
            }
            HStack(spacing: 8) {
                RcButton(
                    label: hosted == "stopped" ? "Start & connect" : "Connect",
                    enabled: canConnect,
                    fillWidth: true,
                    systemImage: "powerplug.fill",
                    identifier: "connectDevice-\(device.id)",
                    action: onConnect
                )
                Menu {
                    Button("Copy setup for macOS/Linux", systemImage: "doc.on.doc") { onCopyUnix() }
                        .disabled(!canCopy)
                    Button("Copy setup for Windows", systemImage: "doc.on.doc") { onCopyWindows() }
                        .disabled(!canCopy)
                    Button("Share device", systemImage: "square.and.arrow.up") { onShare() }
                    if hosted == nil {
                        Button("Replace device token") { onRotate() }
                    }
                    Divider()
                    Button("Delete device", systemImage: "trash", role: .destructive) { onDelete() }
                        .disabled(hosted != nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(colors.fgMuted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More actions for \(device.name)")
            }
        }
        .padding(12)
    }
}

struct SharedAccessTabs: View {
    let tabs: [(String, Int)]
    @Binding var selected: Int
    @Environment(\.rcColors) private var colors

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    selected = index
                } label: {
                    HStack {
                        Text(tabs[index].0)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text("\(tabs[index].1)")
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(colors.muted)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected == index ? colors.fg : colors.fgMuted)
                    .background(selected == index ? colors.panel : colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(3)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
    }
}

struct SharedAccessCardView: View {
    let title: String
    let subtitle: String
    let username: String
    let incoming: Bool
    let permissions: [String]
    let lastAccessedAt: String?
    let events: [(String, String)]
    let expanded: Bool
    var onOpen: () -> Void
    var onEdit: (() -> Void)? = nil
    var onRevoke: (() -> Void)? = nil
    var onToggleHistory: (() -> Void)? = nil
    @Environment(\.rcColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.fg).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(colors.fgMuted).lineLimit(1)
                }
                Spacer()
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Text("Open").font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(colors.accentStrong)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(colors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityIdentifier("Open")
            }
            HStack {
                HStack(spacing: 9) {
                    Text(String(username.prefix(2)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.fgSoft)
                        .frame(width: 36, height: 36)
                        .background(colors.muted)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(incoming ? "Shared by" : "Shared with").font(.system(size: 10)).foregroundStyle(colors.fgMuted)
                        Text(username).font(.system(size: 12, weight: .medium)).foregroundStyle(colors.fg).lineLimit(1)
                    }
                }
                Spacer()
                if !incoming {
                    HStack(spacing: 2) {
                        if let onEdit {
                            Button(action: onEdit) { Image(systemName: "slider.horizontal.3") }
                                .accessibilityLabel("Permissions")
                        }
                        if let onToggleHistory {
                            Button(action: onToggleHistory) { Image(systemName: "clock") }
                                .accessibilityLabel("Access history")
                        }
                        if let onRevoke {
                            Button(action: onRevoke) { Image(systemName: "person.badge.minus") }
                                .foregroundStyle(colors.dangerFg)
                                .accessibilityLabel("Revoke")
                        }
                    }
                    .foregroundStyle(colors.fgMuted)
                }
            }
            HStack(alignment: .top) {
                FlowLayout {
                    ForEach(permissions, id: \.self) { permission in
                        Text(permission)
                            .font(.system(size: 10))
                            .foregroundStyle(colors.fgMuted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(colors.muted)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer()
                if !incoming {
                    Text(lastAccessedAt.flatMap { $0.isEmpty ? nil : "Visited \(formatRelayTime($0))" } ?? "No visits yet")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.fgMuted)
                }
            }
            if !incoming && expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent access").font(.system(size: 12, weight: .medium)).foregroundStyle(colors.fg)
                    if events.isEmpty {
                        Text("No access events yet.").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                    } else {
                        ForEach(Array(events.prefix(8).enumerated()), id: \.offset) { _, event in
                            Text("\(event.0) · \(event.1)").font(.system(size: 12)).foregroundStyle(colors.fgMuted)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.border, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }
}

struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? 280
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + 6
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

struct ShareDeviceSheet: View {
    let deviceName: String
    var busy = false
    var error: String? = nil
    var onShare: (String, String, String, String, Bool) -> Void
    var onClose: () -> Void
    @State private var target = ""
    @State private var label = ""
    @State private var threadAccess = "read"
    @State private var workspaceAccess = "read"
    @State private var canCreate = false
    @Environment(\.rcColors) private var colors

    var body: some View {
        ZStack {
            colors.overlay.ignoresSafeArea().onTapGesture(perform: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share \(deviceName)").font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                    Text("Give another relay account access to this device and its workspaces.").font(.system(size: 13)).foregroundStyle(colors.fgMuted)
                    RcField(label: "Relay account", text: $target, placeholder: "username or email", identifier: "shareTarget")
                    RcField(label: "Label", text: $label, placeholder: "Optional note shown in Shared devices by me", identifier: "shareLabel")
                    picker("Thread access", value: $threadAccess, options: [("read", "View only"), ("control", "Collaborator")])
                    picker("Workspace access", value: $workspaceAccess, options: [("none", "No workspace"), ("read", "Workspace read"), ("write", "Workspace write")])
                    Button { canCreate.toggle() } label: {
                        HStack {
                            Text("Can create new threads").foregroundStyle(colors.fgSoft)
                            Spacer()
                            Text(canCreate ? "On" : "Off").foregroundStyle(colors.fgMuted)
                        }
                    }
                    if let error { Text(error).font(.system(size: 13)).foregroundStyle(colors.dangerFg) }
                    HStack {
                        RcButton(label: "Cancel", primary: false, action: onClose)
                        RcButton(label: busy ? "Sharing..." : "Share device", enabled: !busy && !target.trimmingCharacters(in: .whitespaces).isEmpty, systemImage: "square.and.arrow.up") {
                            onShare(target.trimmingCharacters(in: .whitespaces), label.trimmingCharacters(in: .whitespaces), threadAccess, workspaceAccess, canCreate)
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: 420, maxHeight: 640)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(24)
        }
    }

    private func picker(_ title: String, value: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(colors.fgSoft)
            HStack {
                ForEach(options, id: \.0) { id, label in
                    Button(label) { value.wrappedValue = id }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(value.wrappedValue == id ? colors.fg : colors.fgMuted)
                        .background(value.wrappedValue == id ? colors.accentSoft : colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
