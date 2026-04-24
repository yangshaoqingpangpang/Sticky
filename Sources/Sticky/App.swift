import SwiftUI
import AppKit

@main
struct StickyNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var window: NSWindow!
    private var statusItem: NSStatusItem!
    let store = DataStore()

    private let stripW: CGFloat = 4
    private let panelW: CGFloat = 400
    private(set) var expanded = false
    private var collapseTimer: Timer?
    private var clickMonitor: Any?
    private var dockedSide: Side = .left  // 当前吸附侧

    enum Side { case left, right }

    private var stripView: NSView!
    private var panelContainer: NSView!
    private var deadlineTimer: Timer?
    private var notifiedIds: Set<UUID> = []  // 已提醒过的，避免重复

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        createStatusItem()
        registerShortcut()
        startDeadlineChecker()
    }

    // MARK: - Window

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame

        window = PanelWindow(
            contentRect: NSRect(x: 0, y: vf.origin.y, width: stripW, height: vf.height),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true  // 可拖拽

        let root = TrackingView(frame: NSRect(x: 0, y: 0, width: panelW, height: vf.height))
        root.wantsLayer = true
        root.layer?.masksToBounds = true
        root.onEnter = { [weak self] in self?.handleEnter() }
        root.onExit  = { [weak self] in self?.handleExit() }

        // ── Strip (1px bar + 2px handle) ──
        stripView = NSView(frame: NSRect(x: 0, y: 0, width: stripW, height: vf.height))
        stripView.wantsLayer = true
        let nsAccent = NSColor(store.settings.activeAccent)
        let nsDeep = NSColor(store.settings.activeAccentDeep)
        // 1px full-height bar
        let bar = CALayer()
        bar.backgroundColor = nsAccent.cgColor
        bar.frame = CGRect(x: 0, y: 0, width: 1, height: vf.height)
        stripView.layer?.addSublayer(bar)
        // 2px deeper handle at center
        let handle = CALayer()
        handle.backgroundColor = nsDeep.cgColor
        handle.cornerRadius = 1
        handle.frame = CGRect(x: 0, y: vf.height / 2 - 22, width: 5, height: 44)
        stripView.layer?.addSublayer(handle)

        // ── Panel container ──
        panelContainer = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: vf.height))
        panelContainer.wantsLayer = true
        panelContainer.autoresizingMask = [.width, .height]
        panelContainer.isHidden = true
        updatePanelMask(height: vf.height)

        let visual = NSVisualEffectView(frame: panelContainer.bounds)
        visual.material = .sidebar
        visual.state = .active
        visual.blendingMode = .behindWindow
        visual.autoresizingMask = [.width, .height]
        panelContainer.addSubview(visual)

        let hosting = NSHostingView(rootView:
            ContentView(store: store).environment(\.colorScheme, .light)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            hosting.widthAnchor.constraint(equalToConstant: panelW),
        ])

        root.addSubview(panelContainer)
        root.addSubview(stripView)

        window.contentView = root
        window.orderFront(nil)
    }

    /// 根据吸附侧更新圆角 mask（左贴→右圆角，右贴→左圆角）
    private func updatePanelMask(height: CGFloat) {
        let r: CGFloat = 22
        let w = panelW
        let mask = CAShapeLayer()
        let p = CGMutablePath()

        if dockedSide == .left {
            // 左侧直角，右侧圆角
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: w - r, y: height))
            p.addArc(center: CGPoint(x: w - r, y: height - r), radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: true)
            p.addLine(to: CGPoint(x: w, y: r))
            p.addArc(center: CGPoint(x: w - r, y: r), radius: r, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
            p.addLine(to: .zero)
        } else {
            // 右侧直角，左侧圆角
            p.move(to: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: height))
            p.addLine(to: CGPoint(x: r, y: height))
            p.addArc(center: CGPoint(x: r, y: height - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: false)
            p.addLine(to: CGPoint(x: w, y: 0))
        }
        p.closeSubpath()
        mask.path = p
        panelContainer.layer?.mask = mask
    }

    // MARK: - Snap to nearest edge after drag

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let mid = window.frame.origin.x + window.frame.width / 2
        let screenMid = vf.origin.x + vf.width / 2

        let newSide: Side = mid < screenMid ? .left : .right
        if newSide != dockedSide {
            dockedSide = newSide
            updatePanelMask(height: window.frame.height)
        }

        // 只吸附左右，保持当前 Y 和高度不变
        let x: CGFloat = dockedSide == .left ? vf.origin.x : vf.maxX - (expanded ? panelW : stripW)
        let targetFrame = NSRect(x: x, y: window.frame.origin.y, width: expanded ? panelW : stripW, height: window.frame.height)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !expanded, let screen = NSScreen.main else { return }
        expanded = true
        collapseTimer?.invalidate()

        stripView.isHidden = true
        panelContainer.isHidden = false

        let vf = screen.visibleFrame
        let x: CGFloat = dockedSide == .left ? vf.origin.x : vf.maxX - panelW

        window.hasShadow = true
        window.isMovableByWindowBackground = false  // 展开时禁止拖拽，否则表单无法点击
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(NSRect(x: x, y: window.frame.origin.y, width: panelW, height: window.frame.height), display: true)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapse()
        }
    }

    func collapse() {
        guard expanded, let screen = NSScreen.main else { return }
        expanded = false
        collapseTimer?.invalidate()
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }

        store.sortTodos()
        snapToEdge()  // 收起时吸附到最近边缘

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.panelContainer.isHidden = true
            self?.stripView.isHidden = false
            self?.window.hasShadow = false
            self?.window.isMovableByWindowBackground = true
        }
    }

    private func handleEnter() {
        collapseTimer?.invalidate()
        if !expanded { expand() }
    }

    private func handleExit() {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    @objc func toggle() {
        if expanded { collapse() } else { expand() }
    }

    func startScreenCapture() {
        NSLog("[Sticky] startScreenCapture called")
        collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSLog("[Sticky] launching ScreenCaptureManager")
            ScreenCaptureManager.shared.start { [weak self] image in
                NSLog("[Sticky] capture done, size=\(image.size)")
                guard let self else { return }
                self.store.addTodo(text: "截图", color: .red, images: [image])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.expand()
                }
            }
        }
    }

    // MARK: - Status item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "便笺")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏  ⌘⇧N", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    // MARK: - Shortcut

    /// 把事件转成显示字符串，如 "⌘⇧S"
    private func eventToCombo(_ e: NSEvent) -> String {
        var parts: [String] = []
        if e.modifierFlags.contains(.command) { parts.append("⌘") }
        if e.modifierFlags.contains(.control) { parts.append("⌃") }
        if e.modifierFlags.contains(.option) { parts.append("⌥") }
        if e.modifierFlags.contains(.shift) { parts.append("⇧") }
        if let c = e.charactersIgnoringModifiers, !c.isEmpty {
            parts.append(c.count == 1 ? c.uppercased() : c)
        }
        return parts.joined()
    }

    private func registerShortcut() {
        let handleKey: (NSEvent) -> Bool = { [weak self] e in
            guard let self else { return false }
            let combo = self.eventToCombo(e)
            // 面板切换：固定 ⌘⇧N
            if combo == "⌘⇧N" {
                DispatchQueue.main.async { self.toggle() }
                return true
            }
            // 截图：读取配置的快捷键
            if combo == self.store.settings.screenshotShortcut {
                DispatchQueue.main.async { self.startScreenCapture() }
                return true
            }
            // Esc
            if e.keyCode == 53 {
                DispatchQueue.main.async { self.collapse() }
                return true
            }
            return false
        }

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            _ = handleKey(e)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handleKey(e) ? nil : e
        }

        // 拖拽结束后吸附到最近边缘
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let w = n.object as? NSWindow, w === self.window else { return }
            // 延迟判断，等拖拽结束
            self.collapseTimer?.invalidate()
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.didFinishDrag), object: nil)
            self.perform(#selector(self.didFinishDrag), with: nil, afterDelay: 0.3)
        }
    }

    @objc private func didFinishDrag() {
        if !expanded { snapToEdge() }
    }

    // MARK: - Deadline checker (每分钟检测)

    private func startDeadlineChecker() {
        NSLog("[DDL] 启动定时检测，间隔30秒")
        // 立即检查一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.checkDeadlines() }
        // 每30秒检查
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkDeadlines() }
        }
    }

    private func checkDeadlines() {
        let now = Date()
        var triggered: [String] = []

        for todo in store.todos {
            guard !todo.isDone, let dl = todo.deadline, !notifiedIds.contains(todo.id) else { continue }
            let remaining = dl.timeIntervalSince(now)
            NSLog("[DDL] 检查: \(todo.text.prefix(15)) | 剩余\(Int(remaining))秒")
            // 到期前5分钟内 或 已过期（但不超过24小时）
            if remaining < 300 && remaining > -86400 {
                notifiedIds.insert(todo.id)
                triggered.append(todo.text)
            }
        }

        // 一次发送所有触发的通知
        for text in triggered {
            sendNotification(title: "待办提醒", body: text)
            NSLog("[DDL] ✅ 已发送通知: \(text.prefix(20))")
        }

        if triggered.isEmpty {
            NSLog("[DDL] 本次检查无触发（共\(store.todos.count)条待办）")
        }
    }

    private func sendNotification(title: String, body: String) {
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        let script = "display notification \"\(escaped)\" with title \"便笺 · \(title)\" sound name \"Glass\""
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
    }
}

// MARK: - PanelWindow (borderless 但可交互)

final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - TrackingView

final class TrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit:  (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }
    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent)  { onExit?() }
}
