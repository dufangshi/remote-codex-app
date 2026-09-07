import SwiftUI
import UIKit

struct ScreenEdgeBackSwipe: UIViewRepresentable {
    var enabled: Bool
    var onBack: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBack: onBack)
    }

    func makeUIView(context: Context) -> UIView {
        let view = EdgeBackView()
        view.isUserInteractionEnabled = false
        let gesture = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle))
        gesture.edges = .left
        view.edgeGesture = gesture
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onBack = onBack
        context.coordinator.enabled = enabled
        guard let view = view as? EdgeBackView else { return }
        if enabled {
            view.attach(to: view.window)
        }
    }

    final class Coordinator {
        var onBack: () -> Void
        var enabled = true
        init(onBack: @escaping () -> Void) { self.onBack = onBack }

        @objc func handle(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard enabled, gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            if translation.x > 48 {
                onBack()
            }
        }
    }
}

private final class EdgeBackView: UIView {
    var edgeGesture: UIScreenEdgePanGestureRecognizer?

    func attach(to window: UIWindow?) {
        guard let gesture = edgeGesture else { return }
        if let window, gesture.view !== window {
            gesture.view?.removeGestureRecognizer(gesture)
            window.addGestureRecognizer(gesture)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach(to: window)
    }
}

struct RcButton: View {
    let label: String
    var primary = true
    var enabled = true
    var fillWidth = true
    var systemImage: String? = nil
    var identifier: String? = nil
    let action: () -> Void

    @Environment(\.rcColors) private var colors

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(label)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(minHeight: Rc.touch)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .foregroundStyle(primary ? colors.accentSolidFg : colors.fg)
            .background(primary ? (enabled ? colors.accentSolid : colors.muted) : colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rc.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Rc.radius, style: .continuous)
                    .stroke(primary ? Color.clear : colors.border, lineWidth: 1)
            )
        }
        .disabled(!enabled)
        .accessibilityIdentifier(identifier ?? label)
    }
}

struct ConfirmDialog: View {
    let title: String
    let description: String
    var confirmLabel = "Confirm"
    var busy = false
    var onConfirm: () -> Void
    var onCancel: () -> Void
    @Environment(\.rcColors) private var colors

    var body: some View {
        ZStack {
            colors.overlay.ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                Text(description).font(.system(size: 14)).foregroundStyle(colors.fgMuted)
                HStack(spacing: 8) {
                    RcButton(label: "Cancel", primary: false, action: onCancel)
                    RcButton(label: busy ? "Working..." : confirmLabel, enabled: !busy, identifier: "confirmOk", action: onConfirm)
                }
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(24)
        }
        .accessibilityIdentifier("confirmDialog")
    }
}

struct PromptDialog: View {
    let title: String
    let label: String
    @Binding var value: String
    var busy = false
    var onSubmit: () -> Void
    var onCancel: () -> Void
    @Environment(\.rcColors) private var colors

    var body: some View {
        ZStack {
            colors.overlay.ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(colors.fg)
                RcField(label: label, text: $value, identifier: "dialogField")
                HStack(spacing: 8) {
                    RcButton(label: "Cancel", primary: false, action: onCancel)
                    RcButton(label: busy ? "Saving..." : "Save", enabled: !busy && !value.trimmingCharacters(in: .whitespaces).isEmpty, identifier: "dialogSave", action: onSubmit)
                }
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(colors.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.border, lineWidth: 1))
            .padding(24)
        }
    }
}

struct HostedButton: UIViewRepresentable {
    let title: String
    let identifier: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.92, green: 0.67, blue: 0.25, alpha: 1)
        button.layer.cornerRadius = 6
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        button.isAccessibilityElement = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 320, height: 44)
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

struct RcField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var secure = false
    var identifier: String? = nil

    @Environment(\.rcColors) private var colors
    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(colors.fgSoft)
            HStack {
                Group {
                    if secure && !visible {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.none)
                .foregroundStyle(colors.fg)
                .accessibilityIdentifier(identifier ?? label)
                .submitLabel(.done)
                if secure {
                    Button {
                        visible.toggle()
                    } label: {
                        Image(systemName: visible ? "eye.slash" : "eye")
                            .foregroundStyle(colors.fgMuted)
                    }
                    .accessibilityIdentifier(visible ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Rc.touch)
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Rc.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Rc.radius, style: .continuous)
                    .stroke(colors.border, lineWidth: 1)
            )
        }
    }
}

struct NoticeView: View {
    let text: String
    var tone: Tone = .danger
    @Environment(\.rcColors) private var colors

    enum Tone { case danger, success, accent }

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(fg)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: Rc.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Rc.radius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .accessibilityIdentifier("notice")
    }

    private var bg: Color {
        switch tone {
        case .danger: return colors.dangerBg
        case .success: return colors.muted
        case .accent: return colors.accentSoft
        }
    }
    private var fg: Color {
        switch tone {
        case .danger: return colors.dangerFg
        case .success: return colors.successFg
        case .accent: return colors.accentStrong
        }
    }
    private var border: Color {
        switch tone {
        case .danger: return colors.dangerBorder
        case .success: return colors.border
        case .accent: return colors.accentBorder
        }
    }
}

struct BrandMark: View {
    @Environment(\.rcColors) private var colors
    var body: some View {
        Text("RC")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(colors.accentStrong)
            .frame(width: 36, height: 36)
            .background(colors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ProductHeader: View {
    let title: String
    var backLabel: String? = nil
    var onBack: (() -> Void)? = nil
    var onOpenNav: (() -> Void)? = nil
    var onOpenAccount: (() -> Void)? = nil
    var accountLabel: String? = nil
    var trailing: AnyView? = nil

    @Environment(\.rcColors) private var colors

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if let onOpenNav {
                    headerIcon("line.3.horizontal", "Open Navigation", onOpenNav)
                }
                if let onBack {
                    headerIcon("chevron.left", backLabel ?? "Back", onBack)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(colors.fg)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("pageTitle")
                if let trailing { trailing }
                if let onOpenAccount, let accountLabel, !accountLabel.isEmpty {
                    Button(action: onOpenAccount) {
                        Text(String(accountLabel.prefix(2)).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.fg)
                            .frame(width: 44, height: 44)
                            .background(colors.surfaceStrong)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(colors.border, lineWidth: 1))
                    }
                    .accessibilityIdentifier("accountMenuButton")
                    .accessibilityLabel("Relay account menu for \(accountLabel)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(colors.appBg.opacity(0.94))
            Rectangle().fill(colors.border).frame(height: 1)
        }
    }

    private func headerIcon(_ system: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .foregroundStyle(colors.fg)
                .frame(width: 44, height: 44)
        }
        .accessibilityIdentifier(label)
        .accessibilityLabel(label)
    }
}

struct StatusDot: View {
    var online: Bool
    @Environment(\.rcColors) private var colors
    var body: some View {
        Circle()
            .fill(online ? colors.successFg : colors.fgMuted)
            .frame(width: 10, height: 10)
    }
}

private struct RcColorsKey: EnvironmentKey {
    static let defaultValue = RcColors.dark
}

extension EnvironmentValues {
    var rcColors: RcColors {
        get { self[RcColorsKey.self] }
        set { self[RcColorsKey.self] = newValue }
    }
}
