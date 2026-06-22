import SwiftUI
import AppKit

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let sizeModeChanged = Notification.Name("sizeModeChanged")
    static let demoNav = Notification.Name("demoNav")   // demo 截图模式:全局快捷键切页
}

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
    // demo 截图模式:面板钉住不收起 + ⌃1..⌃6 切页(环境变量 STICKY_DEMO=1 开启,正常使用不受影响)
    private let demoMode = ProcessInfo.processInfo.environment["STICKY_DEMO"] == "1"
    private(set) var expanded = false
    private var collapseTimer: Timer?
    private var clickMonitor: Any?
    private var dockedSide: Side = .left  // 当前吸附侧

    enum Side { case left, right }

    private var stripView: NSView!
    private var panelContainer: NSView!
    private var hostingWidthConstraint: NSLayoutConstraint!
    private var stripBarLayer: CALayer?
    private var stripHandleLayer: CALayer?
    private var deadlineTimer: Timer?
    private var aiSearchTimer: Timer?
    private var notifiedIds: Set<UUID> = []  // 已提醒过的，避免重复

    // 尺寸档驱动:大 400×全高;小 300×半高(顶部对齐,从 menu bar 下沿向下)
    private var panelW: CGFloat {
        store.settings.sizeMode == .large ? 400 : 300
    }
    private func panelH(_ vf: CGRect) -> CGFloat {
        store.settings.sizeMode == .large ? vf.height : vf.height / 2
    }
    /// 窗口左下角 y:默认从 vf 顶部往下 panelH(大档=贴顶全高;小档=贴 menu bar 下沿)
    private func panelY(_ vf: CGRect) -> CGFloat {
        vf.maxY - panelH(vf)
    }
    /// 小尺寸拖拽后记忆的垂直位置(nil=默认贴顶)。大尺寸是全高,无垂直自由度,忽略此值。
    private var dockedY: CGFloat?
    /// 实际生效的 y:小档且有拖拽记忆 → 用记忆值(clamp 在屏幕内);否则默认贴顶
    private func effectiveY(_ vf: CGRect) -> CGFloat {
        let h = panelH(vf)
        guard store.settings.sizeMode == .small, let y = dockedY else { return panelY(vf) }
        return min(max(y, vf.origin.y), vf.maxY - h)
    }

    /// 窗口所在屏幕（多屏安全：优先用窗口所在屏幕，回退到主屏幕）
    private var currentScreen: NSScreen {
        window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        createStatusItem()
        registerShortcut()
        startDeadlineChecker()
        startAISearchTimer()

        // 监听屏幕配置变化（插拔外接屏、分辨率改变）
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.adaptToCurrentScreen()
        }

        // 监听尺寸档切换
        NotificationCenter.default.addObserver(forName: .sizeModeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applySizeMode()
        }

        if demoMode {
            // 截图模式:直接钉开,不做启动收缩动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.expand() }
        } else {
            // 启动时先展开一下再收起,让用户感知到"收缩"动作的存在
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.expand()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    self?.collapse()
                }
            }
        }
    }

    // MARK: - Window

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let h = panelH(vf)

        window = PanelWindow(
            contentRect: NSRect(x: 0, y: effectiveY(vf), width: stripW, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true  // 可拖拽
        // 关键:panel 只在需要键盘输入(如 text field)时才变 key,普通鼠标点击直接 dispatch 到 contentView,
        // 不被系统"激活窗口"流程截获——这是片段第一下点击能立即复制的根因开关。
        // 参考:KeyboardCowboy / Strongbox / SpotMenu 等 sidebar/palette 类项目通用方案。
        (window as? NSPanel)?.becomesKeyOnlyIfNeeded = true

        let root = TrackingView(frame: NSRect(x: 0, y: 0, width: panelW, height: h))
        root.wantsLayer = true
        root.layer?.masksToBounds = true
        root.onEnter = { [weak self] in self?.handleEnter() }
        root.onExit  = { [weak self] in self?.handleExit() }

        // ── Strip (1px bar + 2px handle) ──
        stripView = NSView(frame: NSRect(x: 0, y: 0, width: stripW, height: h))
        stripView.wantsLayer = true
        let nsAccent = NSColor(store.settings.activeAccent)
        let nsDeep = NSColor(store.settings.activeAccentDeep)
        // 1px full-height bar
        let bar = CALayer()
        bar.backgroundColor = nsAccent.cgColor
        bar.frame = CGRect(x: 0, y: 0, width: 1, height: h)
        stripView.layer?.addSublayer(bar)
        stripBarLayer = bar
        // 2px deeper handle at center
        let handle = CALayer()
        handle.backgroundColor = nsDeep.cgColor
        handle.cornerRadius = 1
        handle.frame = CGRect(x: 0, y: h / 2 - 22, width: 5, height: 44)
        stripView.layer?.addSublayer(handle)
        stripHandleLayer = handle

        // ── Panel container ──
        panelContainer = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: h))
        panelContainer.wantsLayer = true
        panelContainer.autoresizingMask = [.width, .height]
        panelContainer.isHidden = true
        updatePanelMask(height: h)

        // Native Utility:实色白底取代毛玻璃(#f9f9ff)
        let visual = NSView(frame: panelContainer.bounds)
        visual.wantsLayer = true
        visual.layer?.backgroundColor = NSColor(red: 0.976, green: 0.976, blue: 1.0, alpha: 1.0).cgColor
        visual.autoresizingMask = [.width, .height]
        panelContainer.addSubview(visual)

        let hosting = FirstMouseHostingView(rootView:
            ContentView(store: store).environment(\.colorScheme, .light)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        panelContainer.addSubview(hosting)
        let widthC = hosting.widthAnchor.constraint(equalToConstant: panelW)
        hostingWidthConstraint = widthC
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: panelContainer.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: panelContainer.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: panelContainer.leadingAnchor),
            widthC,
        ])

        root.addSubview(panelContainer)
        root.addSubview(stripView)

        window.contentView = root
        window.orderFront(nil)
    }

    /// 切换尺寸档后:更新约束 + window frame,panelContainer 通过 autoresizingMask 自动跟随,避免与手动 frame 冲突
    private func applySizeMode() {
        let vf = currentScreen.visibleFrame
        let h = panelH(vf)
        let w = panelW

        // hosting 宽度约束立即更新,让 SwiftUI ContentView 用新宽度排版
        hostingWidthConstraint?.constant = w

        let x: CGFloat
        let frameW: CGFloat = expanded ? w : stripW
        if expanded {
            x = dockedSide == .left ? vf.origin.x : vf.maxX - w
        } else {
            x = dockedSide == .left ? vf.origin.x : vf.maxX - stripW
        }

        // window setFrame 会触发 contentView (root) resize,panelContainer 因为 autoresizingMask 自动跟
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(NSRect(x: x, y: effectiveY(vf), width: frameW, height: h), display: true)
        } completionHandler: { [weak self] in
            // 动画完成后再更新 strip(没用 autoresize)和 mask,确保跟最终 frame 同步
            self?.stripView.frame = NSRect(x: 0, y: 0, width: self?.stripW ?? 4, height: h)
            self?.stripBarLayer?.frame = CGRect(x: 0, y: 0, width: 1, height: h)
            self?.stripHandleLayer?.frame = CGRect(x: 0, y: h / 2 - 22, width: 5, height: 44)
            self?.updatePanelMask(height: h)
        }
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

    // MARK: - 多屏适配

    /// 窗口拖到新屏幕后、或外接屏插拔时，重新适配窗口高度和位置
    private func adaptToCurrentScreen() {
        let vf = currentScreen.visibleFrame
        let h = panelH(vf)
        let x: CGFloat
        if expanded {
            x = dockedSide == .left ? vf.origin.x : vf.maxX - panelW
        } else {
            x = dockedSide == .left ? vf.origin.x : vf.maxX - stripW
        }
        let targetFrame = NSRect(x: x, y: effectiveY(vf), width: expanded ? panelW : stripW, height: h)
        window.setFrame(targetFrame, display: true)
        updatePanelMask(height: h)
    }

    // MARK: - Snap to nearest edge after drag

    private func snapToEdge() {
        let vf = currentScreen.visibleFrame
        let h = panelH(vf)
        let mid = window.frame.origin.x + window.frame.width / 2
        let screenMid = vf.origin.x + vf.width / 2

        let newSide: Side = mid < screenMid ? .left : .right
        if newSide != dockedSide {
            dockedSide = newSide
            updatePanelMask(height: h)
        }

        // 小尺寸:记忆当前拖拽到的垂直位置(只吸附水平边,垂直保持)
        if store.settings.sizeMode == .small {
            dockedY = min(max(window.frame.origin.y, vf.origin.y), vf.maxY - h)
        }

        // 吸附到窗口所在屏幕的边缘，高度适配该屏幕
        let x: CGFloat = dockedSide == .left ? vf.origin.x : vf.maxX - (expanded ? panelW : stripW)
        let targetFrame = NSRect(x: x, y: effectiveY(vf), width: expanded ? panelW : stripW, height: h)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !expanded else { return }
        expanded = true
        collapseTimer?.invalidate()

        stripView.isHidden = true
        panelContainer.isHidden = false

        let vf = currentScreen.visibleFrame
        let h = panelH(vf)
        let x: CGFloat = dockedSide == .left ? vf.origin.x : vf.maxX - panelW

        window.hasShadow = true
        window.isMovableByWindowBackground = false  // 展开时禁止拖拽，否则表单无法点击
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(NSRect(x: x, y: effectiveY(vf), width: panelW, height: h), display: true)
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapse()
        }

        // 首次展开面板时触发新手引导
        if !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }
        }
    }

    func collapse() {
        if demoMode { return }   // 截图模式钉住不收
        guard expanded else { return }
        expanded = false
        collapseTimer?.invalidate()
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }

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
        collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            ScreenCaptureManager.shared.start { [weak self] image in
                guard let self else { return }
                // 配了大模型走视觉提取(异步),否则放图+兜底文案
                Task { [weak self] in
                    await self?.store.addTodosFromScreenshot(image)
                }
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
        // 显示/隐藏 → AppDelegate.toggle(target=self)
        let toggleItem = NSMenuItem(title: "显示/隐藏  ⌘⇧N", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        // 退出 → NSApplication.terminate(必须 target=NSApp,否则 AppDelegate 不响应 terminate: 会被禁用变灰)
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
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
            // demo 截图模式:⌃1..⌃6 切页
            if self.demoMode {
                let map: [String: String] = ["⌃1": "todos", "⌃2": "notes", "⌃3": "settings", "⌃4": "newTodo", "⌃5": "log", "⌃6": "small", "⌃7": "large"]
                if let target = map[combo] {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .demoNav, object: target) }
                    return true
                }
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
            self.collapseTimer?.invalidate()
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.didFinishDrag), object: nil)
            self.perform(#selector(self.didFinishDrag), with: nil, afterDelay: 0.3)
        }

        // 窗口移到新屏幕后适配
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let w = n.object as? NSWindow, w === self.window else { return }
            self.adaptToCurrentScreen()
        }
    }

    @objc private func didFinishDrag() {
        if !expanded { snapToEdge() }
    }

    // MARK: - Deadline checker (每30秒检测)

    private func startDeadlineChecker() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.checkDeadlines() }
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkDeadlines() }
        }
    }

    /// 每分钟触发一次 AI 帮手检索批次(每批最多 3 条未完成未检索的待办)
    private func startAISearchTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.store.runAISearchBatch() }
        aiSearchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.store.runAISearchBatch() }
        }
    }

    private func checkDeadlines() {
        let now = Date()
        for todo in store.todos {
            guard !todo.isDone, let dl = todo.deadline, !notifiedIds.contains(todo.id) else { continue }
            let remaining = dl.timeIntervalSince(now)
            if remaining < 300 && remaining > -86400 {
                notifiedIds.insert(todo.id)
                sendNotification(title: "待办提醒", body: todo.text)
            }
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

// MARK: - PanelWindow (NSPanel + .nonactivatingPanel:浮动且第一下点击直接生效)
// 关键:继承 NSPanel 才能用 .nonactivatingPanel styleMask,这样窗口接收 mouse 不需要先激活 app

final class PanelWindow: NSPanel {
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
    // 浮动 accessory app 窗口在 inactive 时,第一次 mouseDown 被系统用于"激活窗口"而吞掉。
    // 返回 true 让第一下 mouseDown 直接传给 SwiftUI gesture,避免常用片段需要点两次。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - FirstMouseHostingView (SwiftUI 容器,第一下点击即生效)

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
