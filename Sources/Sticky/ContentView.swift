import SwiftUI
import AppKit

enum PanelPage { case main, anniversary, settings }
enum MainTab { case todos, notes }

struct ContentView: View {
    @ObservedObject var store: DataStore
    @State private var page: PanelPage = .main
    @State private var activeTab: MainTab = .todos
    @State private var searchText = ""
    @State private var showNewTodo = false
    @State private var showLog = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var onboardingStep: Int? = nil

    private let onboardingSteps: [(id: String, title: String, text: String)] = [
        ("todo", "待办事项工作区", "这里是主工作区，单击可以关闭，点击右侧三杠可以完全删除以及设置死线"),
        ("notes", "灵感区", "这是用于随手记的区域，点右侧的 ✕ 可删除"),
        ("snippets", "常用片段区", "常用短语放这里，点击快速复制，记录密码邮箱很方便"),
        ("settings", "设置区", "这里可以配色，自定义节日，做更懂你的便笺工具。"),
        ("camera", "截屏待办", "点击相机即可截屏，快速生成一张图片待办。"),
    ]

    var body: some View {
        ZStack {
            // Native Utility 白底（取代毛玻璃 + 主题色调）
            Color.nuSurface
                .ignoresSafeArea()

            mainPage.opacity(page == .main ? 1 : 0)
            if page == .settings {
                SettingsView(store: store, page: $page).transition(.move(edge: .trailing))
            }
            if showNewTodo {
                NewTodoOverlay(store: store, isPresented: $showNewTodo).transition(.opacity)
            }
            if showLog {
                LogPanel(onClose: { withAnimation { showLog = false } })
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.35), value: page)
        .animation(.easeOut(duration: 0.2), value: showNewTodo)
        .animation(.easeOut(duration: 0.2), value: showLog)
        .overlayPreferenceValue(OnboardingAnchorKey.self) { anchors in
            if let stepIdx = onboardingStep {
                GeometryReader { proxy in
                    OnboardingOverlay(
                        anchors: anchors, proxy: proxy, step: stepIdx, steps: onboardingSteps,
                        onNext: { advanceOnboarding() }, onSkip: { finishOnboarding() }
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: onboardingStep)
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            guard !hasSeenOnboarding, onboardingStep == nil else { return }
            onboardingStep = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .demoNav)) { note in
            guard let target = note.object as? String else { return }
            showNewTodo = false; showLog = false
            switch target {
            case "todos":    page = .main; activeTab = .todos
            case "notes":    page = .main; activeTab = .notes
            case "settings": page = .settings
            case "newTodo":  page = .main; showNewTodo = true
            case "log":      showLog = true
            case "small":    store.settings.sizeMode = .small; store.save(); NotificationCenter.default.post(name: .sizeModeChanged, object: nil)
            case "large":    store.settings.sizeMode = .large; store.save(); NotificationCenter.default.post(name: .sizeModeChanged, object: nil)
            default: break
            }
        }
    }

    private func advanceOnboarding() {
        guard let s = onboardingStep else { return }
        if s + 1 < onboardingSteps.count { onboardingStep = s + 1 }
        else { finishOnboarding() }
    }

    private func finishOnboarding() {
        hasSeenOnboarding = true
        onboardingStep = nil
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            ZStack {
                // 拖拽指示条（居中，整个区域可拖拽）
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.nuOutlineVariant.opacity(0.7))
                        .frame(width: 36, height: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(WindowDragHandle())

                // 左上角:尺寸档切换(大/小)
                HStack(spacing: 6) {
                    sizeButton(.large, label: "大")
                    sizeButton(.small, label: "小")
                    Spacer()
                }
                .padding(.leading, 22)

                // 按钮（右上角，浮在拖拽区域上方）
                HStack(spacing: 12) {
                    Spacer()
                    Button { AppDelegate.shared?.startScreenCapture() } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.nuOutline)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .onboardingAnchor("camera")
                    Button { withAnimation { page = .settings } } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.nuOutline)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .onboardingAnchor("settings")
                }
                .padding(.trailing, 22)
            }
            .frame(height: 24)
            .padding(.top, 14)

            // Header (日期行点击 → 进入设置页;时间连点 5 次 → 隐藏日志)
            HeaderView(store: store, onSettings: {
                withAnimation { page = .settings }
            }, onShowLog: {
                withAnimation { showLog = true }
            })

            // Separator
            Rectangle().fill(Color.nuOutlineVariant.opacity(0.4)).frame(height: 0.5).padding(.horizontal, 16)

            // Tab bar
            HStack(spacing: 0) {
                tabButton("待办事项", tab: .todos)
                tabButton("灵感", tab: .notes)
                    .onboardingAnchor("notes")
                Spacer()
                if activeTab == .todos {
                    Text("\(filteredTodos.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.nuOutline)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.nuGray6))
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            if activeTab == .todos {
                // Search bar
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(.nuOutline)
                        TextField("搜索待办、片段…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color.nuGray6)
                    .cornerRadius(8)

                    Button { showNewTodo = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(store.settings.activeAccent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 4)

                // Todo list (flex area)
                TodoListView(store: store, todos: filteredTodos)
                    .onboardingAnchor("todo")

                // Quick copy tray
                VStack(spacing: 0) {
                    Rectangle().fill(Color.nuOutlineVariant.opacity(0.4)).frame(height: 0.5)
                    SnippetSection(store: store)
                }
                .background(Color.nuGray6.opacity(0.5))
                .onboardingAnchor("snippets")
            } else {
                NotesPanel(store: store)
            }
        }
    }

    private func sizeButton(_ mode: SizeMode, label: String) -> some View {
        let active = store.settings.sizeMode == mode
        // 大 = 大方块,小 = 小方块,用 SF Symbol 实心矩形区分
        let icon: String = mode == .large ? "square.fill" : "square"
        let iconSize: CGFloat = mode == .large ? 9 : 7
        return Button {
            guard !active else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                store.settings.sizeMode = mode
                store.save()
            }
            NotificationCenter.default.post(name: .sizeModeChanged, object: nil)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(active ? store.settings.activeAccentDeep : .nuOutline)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? Color.nuGray6 : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(label + "尺寸")
    }

    private func tabButton(_ label: String, tab: MainTab) -> some View {
        let active = activeTab == tab
        let small = store.settings.sizeMode == .small
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { activeTab = tab }
        } label: {
            VStack(spacing: 5) {
                Text(label)
                    .font(.system(size: small ? 13 : 15, weight: .semibold))
                    .foregroundColor(active ? .nuOnSurface : .nuOutline)
                // 选中态:主色下划线指示器
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? store.settings.activeAccent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
    }

    var filteredTodos: [Todo] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let base = q.isEmpty ? store.todos : store.todos.filter { $0.text.lowercased().contains(q) }
        return base.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isDone && b.isDone { return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast) }
            if a.isSuperDeadline != b.isSuperDeadline { return a.isSuperDeadline }
            let aHasDL = a.deadline != nil
            let bHasDL = b.deadline != nil
            if aHasDL != bHasDL { return aHasDL }
            if let adl = a.deadline, let bdl = b.deadline { return adl < bdl }
            return a.createdAt > b.createdAt
        }
    }
}

// MARK: - Snippet Section (常用片段)

struct SnippetSection: View {
    @ObservedObject var store: DataStore
    @State private var copiedId: UUID?
    @State private var editingId: UUID?
    @State private var editText = ""
    @State private var showAdd = false
    @State private var newText = ""
    private let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.nuOutline)
                Text("常用片段")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.nuOnSurface)
                Spacer()
                Text("点击复制 · 双击编辑")
                    .font(.system(size: 10.5))
                    .foregroundColor(.nuOutline)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

            // List
            if store.snippets.isEmpty && !showAdd {
                Text("暂无片段")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                // 大档:≤4 条全显示,≥5 条锁 4.5 行;小档:始终锁 2.5 行让出垂直空间
                let maxRows: CGFloat = store.settings.sizeMode == .large ? 4.5 : 2.5
                let threshold = Int(maxRows.rounded(.down))
                if store.snippets.count > threshold {
                    ScrollView { list }.frame(height: rowHeight * maxRows)
                } else {
                    list
                }
            }

            // Add row
            if showAdd {
                HStack(spacing: 6) {
                    TextField("输入片段内容…", text: $newText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit { addSnippet() }
                    Button { addSnippet() } label: {
                        Text("添加").font(.system(size: 11, weight: .medium))
                            .foregroundColor(store.settings.activeAccentDeep)
                    }.buttonStyle(.plain)
                    Button { showAdd = false; newText = "" } label: {
                        Text("取消").font(.system(size: 11)).foregroundColor(Color(white: 0.55))
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 24).padding(.vertical, 6)
            }

            // + 添加按钮
            if !showAdd {
                Button { showAdd = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        Text("添加片段").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(store.settings.activeAccentDeep)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.top, 6)
            }
        }
        .padding(.bottom, 12)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.snippets) { s in
                if editingId == s.id {
                    // Inline editing
                    HStack(spacing: 6) {
                        TextField("", text: $editText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .onSubmit { finishEdit(s) }
                        Button { finishEdit(s) } label: {
                            Text("保存").font(.system(size: 11, weight: .medium))
                                .foregroundColor(store.settings.activeAccentDeep)
                        }.buttonStyle(.plain)
                        Button { editingId = nil } label: {
                            Text("取消").font(.system(size: 11)).foregroundColor(Color(white: 0.55))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                } else {
                    HStack {
                        Text(s.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.nuOnSurfaceVariant)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(copiedId == s.id ? "已复制 ✓" : "")
                            .font(.system(size: 10.5))
                            .foregroundColor(store.settings.activeAccentDeep)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(copiedId == s.id ? Color.nuGray6 : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        ExclusiveGesture(
                            TapGesture(count: 2),
                            TapGesture(count: 1)
                        )
                        .onEnded { value in
                            switch value {
                            case .first:
                                editingId = s.id; editText = s.text
                            case .second:
                                copy(s)
                            }
                        }
                    )
                    .contextMenu {
                        Button("编辑") { editingId = s.id; editText = s.text }
                        Button("删除", role: .destructive) { store.deleteSnippet(s.id) }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func copy(_ s: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s.text, forType: .string)
        copiedId = s.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if copiedId == s.id { copiedId = nil } }
    }

    private func finishEdit(_ s: Snippet) {
        let t = editText.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { store.updateSnippet(s.id, text: t) }
        editingId = nil
    }

    private func addSnippet() {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.addSnippet(text: t)
        newText = ""
        showAdd = false
    }
}

// MARK: - Window drag handle (展开时拖拽窗口)

struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView { DragHandleNSView() }
    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

final class DragHandleNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - Onboarding (首次启动引导遮罩)

struct OnboardingAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func onboardingAnchor(_ id: String) -> some View {
        anchorPreference(key: OnboardingAnchorKey.self, value: .bounds) { [id: $0] }
    }
    // 在暗色遮罩上挖一个圆角矩形透光孔
    func punchHole(_ rect: CGRect, cornerRadius: CGFloat) -> some View {
        mask {
            ZStack {
                Rectangle()
                RoundedRectangle(cornerRadius: cornerRadius)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}

struct OnboardingOverlay: View {
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy
    let step: Int
    let steps: [(id: String, title: String, text: String)]
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        let info = steps[step]
        let rect = anchors[info.id].map { proxy[$0].insetBy(dx: -6, dy: -6) }
        return ZStack(alignment: .topLeading) {
            Group {
                if let rect { Color.black.opacity(0.62).punchHole(rect, cornerRadius: 12) }
                else { Color.black.opacity(0.62) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onNext() }

            if let rect {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }

            bubble(info: info, rect: rect)
        }
    }

    @ViewBuilder
    private func bubble(info: (id: String, title: String, text: String), rect: CGRect?) -> some View {
        let bubbleWidth = min(proxy.size.width - 40, 280)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(step + 1)/\(steps.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.55))
                Spacer()
                Button(action: onSkip) {
                    Text("跳过").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            Text(info.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            Text(info.text)
                .font(.system(size: 12.5)).foregroundColor(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: onNext) {
                    Text(step == steps.count - 1 ? "知道了" : "下一步")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.white).cornerRadius(8)
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: bubbleWidth, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.15)))
        .position(bubblePosition(rect: rect, width: bubbleWidth))
    }

    private func bubblePosition(rect: CGRect?, width: CGFloat) -> CGPoint {
        let w = proxy.size.width, h = proxy.size.height
        guard let rect else { return CGPoint(x: w / 2, y: h / 2) }
        let estH: CGFloat = 132
        let below = rect.maxY < h * 0.5
        let x = min(max(rect.midX, width / 2 + 20), w - width / 2 - 20)
        let y = below
            ? min(rect.maxY + estH / 2 + 16, h - estH / 2 - 12)
            : max(rect.minY - estH / 2 - 16, estH / 2 + 12)
        return CGPoint(x: x, y: y)
    }
}

