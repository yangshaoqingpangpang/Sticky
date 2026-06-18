import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Todo List (单列列表)

struct TodoListView: View {
    @ObservedObject var store: DataStore
    let todos: [Todo]
    @State private var viewingImages: [NSImage] = []
    @State private var viewingIndex = 0
    @State private var showViewer = false
    @State private var draggingTodoID: UUID?

    var body: some View {
        ZStack {
            if todos.isEmpty {
                Text("点击 ＋ 新建")
                    .font(.system(size: 13)).foregroundColor(Color(white: 0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(todos) { todo in
                            TodoRow(todo: todo, store: store, draggingTodoID: $draggingTodoID) { imgs, idx in
                                viewingImages = imgs; viewingIndex = idx; showViewer = true
                            }
                            .onDrop(of: [UTType.text], delegate: TodoReorderDelegate(
                                targetID: todo.id, store: store, draggingTodoID: $draggingTodoID
                            ))
                            .opacity(draggingTodoID == todo.id ? 0.4 : 1)
                            // 死线行用整块暖色背景,连续两条之间需要透气以免视觉粘连
                            .padding(.vertical, todo.isSuperDeadline && !todo.isDone ? 3 : 0)
                            if todo.id != todos.last?.id, !todo.isSuperDeadline {
                                Rectangle().fill(Color(white: 0.93)).frame(height: 0.5).padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6)
                }
            }

            if showViewer {
                ImageViewer(images: viewingImages, index: $viewingIndex) { showViewer = false }
            }
        }
    }
}

// MARK: - Todo Row

struct TodoRow: View {
    let todo: Todo
    @ObservedObject var store: DataStore
    @Binding var draggingTodoID: UUID?
    var onImageTap: ([NSImage], Int) -> Void
    @State private var isHovered = false
    @State private var shakeOffset: CGFloat = 0
    @State private var slideOpen = false
    @State private var aiExpanded = false
    @State private var editing = false
    @State private var editText = ""
    @State private var editDayIndex: Int? = nil
    @State private var editHour: Int = 10
    @State private var editMinute: Int = 0

    private var overdue: Bool { store.isOverdue(todo) }
    private var aiResultReady: Bool { todo.aiSearchState == .done && (todo.aiConclusion?.isEmpty == false) }

    // 方案 A：死线条目 = 左侧细红竖条（之前的亮红）+ 浅暖底
    private let deadlineRed = Color.red
    private let deadlineBG = Color(red: 0.96, green: 0.92, blue: 0.88)

    // AI 帮手展开区:结论 / 来源
    @ViewBuilder private var aiResultView: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch todo.aiSearchState {
            case .searching:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 10, height: 10)
                    Text("AI 检索中…").font(.system(size: 10.5)).foregroundColor(.secondary)
                }
            case .done:
                if let c = todo.aiConclusion, !c.isEmpty {
                    aiResultLine(label: "结论", text: c)
                }
                if let s = todo.aiSource, !s.isEmpty {
                    aiResultLine(label: "来源", text: s)
                }
                HStack {
                    Spacer()
                    Button {
                        withAnimation { aiExpanded = false }
                        store.dismissAISearch(todo.id)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle").font(.system(size: 9))
                            Text("不采纳").font(.system(size: 10))
                        }.foregroundColor(.secondary)
                    }.buttonStyle(.plain).help("删除此建议，不再显示")
                }
            case .failed:
                HStack(spacing: 5) {
                    Text("检索失败").font(.system(size: 10.5)).foregroundColor(.orange)
                    Button("重试") { store.startAISearch(todo.id) }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .buttonStyle(.plain)
                }
            case .skipped:
                HStack {
                    Text("私人事务，无需 AI 建议")
                        .font(.system(size: 10.5)).foregroundColor(.secondary)
                    Spacer()
                    Button("仍要检索") { store.startAISearch(todo.id, force: true) }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .buttonStyle(.plain)
                }
            case .dismissed:
                EmptyView()
            case .idle:
                Text(store.aiConfigured ? "等待检索…" : "请先在设置中配置大模型")
                    .font(.system(size: 10.5)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(store.settings.activeAccent.opacity(0.07)))
        .padding(.top, 4)
    }

    private func aiResultLine(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text("\(label)：").font(.system(size: 10.5, weight: .semibold)).foregroundColor(store.settings.activeAccentDeep)
            Text(text).font(.system(size: 10.5)).foregroundColor(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧滑出按钮
            if slideOpen {
                VStack(spacing: 6) {
                    Button { startEdit(); slideOpen = false } label: {
                        Text("修改").font(.system(size: 10, weight: .medium)).foregroundColor(Color(white: 0.5))
                    }.buttonStyle(.plain)
                    Button { withAnimation { store.deleteTodo(todo.id) } } label: {
                        Text("删除").font(.system(size: 10, weight: .medium)).foregroundColor(.red.opacity(0.7))
                    }.buttonStyle(.plain)
                    if !todo.isDone {
                        Button { withAnimation { store.toggleSuperDeadline(todo.id) }; slideOpen = false } label: {
                            Text(todo.isSuperDeadline ? "取消" : "死线")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(todo.isSuperDeadline ? Color(white: 0.5) : .white)
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(todo.isSuperDeadline ? Color.clear : Color.red.opacity(0.8))
                                .cornerRadius(3)
                        }.buttonStyle(.plain)
                    }
                }
                .frame(width: 32)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // 主行
            HStack(alignment: .top, spacing: 10) {
                // 色块（死线项用左侧竖条代替，这里隐藏小点但保留 8pt 占位，保证文字左对齐一致）
                Circle().fill(todo.color.color)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                    .opacity(todo.isSuperDeadline && !todo.isDone ? 0 : (isHovered ? 0.95 : (todo.isDone ? 0.3 : 0.6)))
                    .padding(.top, 5)

                // 内容
                VStack(alignment: .leading, spacing: 3) {
                    if editing {
                        TextField("", text: $editText, onCommit: { saveEdit() })
                            .textFieldStyle(.roundedBorder).font(.system(size: 13))

                        // DDL 编辑：7天卡片
                        Text("截止日期").font(.system(size: 10, weight: .medium)).foregroundColor(Color(white: 0.5))
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { i in
                                let d = editDayDate(i)
                                let sel = editDayIndex == i
                                VStack(spacing: 1) {
                                    Text("\(Calendar.current.component(.day, from: d))").font(.system(size: 10, weight: sel ? .bold : .medium)).monospacedDigit()
                                    Text(editDayLabel(i)).font(.system(size: 7)).foregroundColor(sel ? store.settings.activeAccentDeep : Color(white: 0.5))
                                }
                                .frame(width: 32, height: 28)
                                .background(RoundedRectangle(cornerRadius: 5).fill(sel ? store.settings.activeSwatch : Color(white: 0.96)))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(sel ? store.settings.activeAccent.opacity(0.4) : Color(white: 0.9), lineWidth: 0.5))
                                .onTapGesture { withAnimation(.easeOut(duration: 0.1)) { editDayIndex = sel ? nil : i } }
                            }
                        }

                        if editDayIndex != nil {
                            HStack(spacing: 2) {
                                ScrollDigit(value: $editHour, range: 0...23, step: 1)
                                Text(":").font(.system(size: 14, weight: .medium)).foregroundColor(Color(white: 0.35))
                                ScrollDigit(value: $editMinute, range: 0...55, step: 5)
                                Spacer()
                            }
                        }

                        HStack(spacing: 8) {
                            Button("保存") { saveEdit() }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(store.settings.activeAccentDeep)
                            Button("取消") { editing = false }
                                .font(.system(size: 11)).foregroundColor(Color(white: 0.5))
                        }.buttonStyle(.plain)
                    } else {
                        let superActive = todo.isSuperDeadline && !todo.isDone
                        Text(todo.text)
                            .font(.system(size: 13, weight: superActive ? .semibold : .regular)).tracking(-0.1)
                            .foregroundColor(todo.isDone ? Color(white: 0.6) : Color(white: 0.13))
                            .strikethrough(todo.isDone, color: Color(white: 0.6))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Text(relativeTime(todo.createdAt))
                                .font(.system(size: 11))
                                .foregroundColor(superActive ? deadlineRed : Color(white: 0.6))
                                .monospacedDigit()
                            if let dl = todo.deadline {
                                let overdueDL = dl < Date()
                                Text("· \(deadlineText(dl))\(superActive && overdueDL ? " · 逾期" : "")")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(todo.isDone ? Color(white: 0.6) : (superActive ? deadlineRed : (overdueDL ? Color.red.opacity(0.7) : store.settings.activeAccentDeep)))
                                    .monospacedDigit()
                            }
                        }

                        if aiExpanded { aiResultView }
                    }
                }

                Spacer(minLength: 4)

                // 缩略图
                if let first = todo.imageNames.first, let img = store.loadImage(name: first) {
                    Button {
                        let all = todo.imageNames.compactMap { store.loadImage(name: $0) }
                        onImageTap(all, 0)
                    } label: {
                        Image(nsImage: img)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 34)
                            .cornerRadius(7).clipped()
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(white: 0.92), lineWidth: 0.5))
                            .overlay(alignment: .bottomTrailing) {
                                if todo.imageNames.count > 1 {
                                    Text("+\(todo.imageNames.count - 1)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(Color.black.opacity(0.55))
                                        .cornerRadius(3).offset(x: -2, y: -2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }

                // AI 帮手按钮（三横线左侧；未完成项显示）
                if !todo.isDone {
                    let dismissed = todo.aiSearchState == .dismissed
                    Button {
                        guard !dismissed else { return }   // 已不采纳:图标可见但不再触发
                        withAnimation(.easeOut(duration: 0.15)) { aiExpanded.toggle() }
                        if aiExpanded, todo.aiSearchState == .idle || todo.aiSearchState == .failed {
                            store.startAISearch(todo.id)
                        }
                    } label: {
                        // 不采纳→灰底禁止符;检索完成→主题色背景+白图标;其余→灰底灰图标
                        Image(systemName: dismissed ? "nosign" : "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(dismissed ? Color(white: 0.55) : (aiResultReady ? .white : Color(white: 0.6)))
                            .frame(width: 18, height: 18)
                            .background(
                                Circle().fill(aiResultReady && !dismissed ? store.settings.activeAccent : Color(white: 0.9))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(dismissed ? "已不采纳" : "AI 帮手")
                    .padding(.top, 4)
                }

                // 三横线按钮（拖拽排序 + 点击菜单）
                VStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(Color(white: 0.72))
                            .frame(width: 12, height: 1.5)
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.15)) { slideOpen.toggle() }
                }
                .onDrag {
                    draggingTodoID = todo.id
                    return NSItemProvider(object: todo.id.uuidString as NSString)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 9).padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(todo.isSuperDeadline && !todo.isDone ? deadlineBG : (isHovered ? Color(white: 0.97) : Color.clear))
            )
            .overlay(alignment: .leading) {
                if todo.isSuperDeadline && !todo.isDone {
                    // 细红竖条：离左缘留缝 + 上下内缩 + 胶囊形
                    Capsule()
                        .fill(deadlineRed)
                        .frame(width: 5)
                        .padding(.vertical, 7)
                        .padding(.leading, 4)
                }
            }
            .opacity(todo.isDone ? 0.65 : 1)
            .onTapGesture {
                if slideOpen { withAnimation(.easeOut(duration: 0.15)) { slideOpen = false } }
                else if !editing { withAnimation(.easeOut(duration: 0.15)) { store.toggleTodo(todo.id) } }
            }
            // 向右滑显示 修改 / 删除 / 死线;向左滑收起
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onEnded { v in
                        guard !editing else { return }
                        let dx = v.translation.width
                        if dx > 28, !slideOpen {
                            withAnimation(.easeOut(duration: 0.18)) { slideOpen = true }
                        } else if dx < -20, slideOpen {
                            withAnimation(.easeOut(duration: 0.18)) { slideOpen = false }
                        }
                    }
            )
        }
        .offset(x: shakeOffset)
        .onHover { isHovered = $0 }
        .onAppear { if overdue { startShake() } }
    }

    private func startEdit() {
        editText = todo.text
        if let dl = todo.deadline {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let dlDay = cal.startOfDay(for: dl)
            let diff = cal.dateComponents([.day], from: today, to: dlDay).day ?? 0
            editDayIndex = (0...6).contains(diff) ? diff : nil
            editHour = cal.component(.hour, from: dl)
            editMinute = (cal.component(.minute, from: dl) / 5) * 5
        } else {
            editDayIndex = nil; editHour = 10; editMinute = 0
        }
        editing = true
    }

    private func saveEdit() {
        let t = editText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { editing = false; return }
        var newDL: Date? = nil
        if let idx = editDayIndex {
            let base = Calendar.current.date(byAdding: .day, value: idx, to: Calendar.current.startOfDay(for: Date()))!
            newDL = Calendar.current.date(bySettingHour: editHour, minute: editMinute, second: 0, of: base)
        }
        store.updateTodo(todo.id, text: t, deadline: newDL)
        editing = false
    }

    private func editDayDate(_ i: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: i, to: Calendar.current.startOfDay(for: Date()))!
    }
    private func editDayLabel(_ i: Int) -> String {
        if i == 0 { return "今天" }
        if i == 1 { return "明天" }
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "EEE"
        return f.string(from: editDayDate(i))
    }

    private func startShake() {
        func step(_ n: Int) {
            guard n < 14 else { shakeOffset = 0; return }
            let dir: CGFloat = n.isMultiple(of: 2) ? 1 : -1
            let amp: CGFloat = 5 * CGFloat(14 - n) / 14
            withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = dir * amp }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { step(n + 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { step(0) }
    }

    private func relativeTime(_ date: Date) -> String {
        let d = Date().timeIntervalSince(date)
        if d < 60 { return "刚刚" }
        if d < 3600 { return "\(Int(d/60))分钟前" }
        if d < 86400 { return "\(Int(d/3600))小时前" }
        let days = Int(d / 86400)
        if days < 7 { return "\(days)天前" }
        let f = DateFormatter(); f.dateFormat = "M月d日"; return f.string(from: date)
    }

    private func deadlineText(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        let cal = Calendar.current
        if cal.isDateInToday(date) { f.dateFormat = "今天 HH:mm" }
        else if cal.isDateInTomorrow(date) { f.dateFormat = "明天 HH:mm" }
        else { f.dateFormat = "M/d HH:mm" }
        return f.string(from: date)
    }
}

// MARK: - Delete shake

struct DeleteShake: ViewModifier {
    @State private var offset: CGFloat = 0
    func body(content: Content) -> some View {
        content.offset(x: offset).onAppear {
            func step(_ n: Int) {
                guard n < 8 else { offset = 0; return }
                let dir: CGFloat = n.isMultiple(of: 2) ? 1 : -1
                withAnimation(.easeInOut(duration: 0.04)) { offset = dir * 3 * CGFloat(8 - n) / 8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { step(n + 1) }
            }
            step(0)
        }
    }
}

// MARK: - New Todo

struct NewTodoOverlay: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool
    @State private var text = ""
    @State private var color: TodoColor = .red
    @State private var images: [NSImage] = []
    @State private var selectedDayIndex: Int? = nil
    @State private var selectedHour: Int = 10
    @State private var selectedMinute: Int = 0

    private let cal = Calendar.current
    private var next7Days: [(date: Date, dayNum: String, label: String)] {
        let wf = DateFormatter(); wf.locale = Locale(identifier: "zh_CN"); wf.dateFormat = "EEE"
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: Date()))!
            let num = "\(cal.component(.day, from: d))"
            let label = i == 0 ? "今天" : (i == 1 ? "明天" : wf.string(from: d))
            return (d, num, label)
        }
    }
    private var computedDeadline: Date? {
        guard let idx = selectedDayIndex else { return nil }
        return cal.date(bySettingHour: selectedHour, minute: selectedMinute, second: 0, of: next7Days[idx].date)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).onTapGesture { isPresented = false }
            VStack(alignment: .leading, spacing: 12) {
                Text("新建待办").font(.system(size: 16, weight: .semibold))
                TextField("输入待办事项…", text: $text).textFieldStyle(.roundedBorder).font(.system(size: 13))

                // DDL: 7天香囊卡片
                Text("截止日期").font(.system(size: 11, weight: .medium)).foregroundColor(Color(white: 0.5))
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { i in
                        let day = next7Days[i]
                        let sel = selectedDayIndex == i
                        VStack(spacing: 1) {
                            Text(day.dayNum).font(.system(size: 12, weight: sel ? .bold : .medium)).monospacedDigit()
                            Text(day.label).font(.system(size: 8))
                                .foregroundColor(sel ? store.settings.activeAccentDeep : Color(white: 0.5))
                        }
                        .frame(width: 38, height: 34)
                        .background(SachetShape().fill(sel ? store.settings.activeSwatch : Color(white: 0.96)))
                        .overlay(SachetShape().stroke(sel ? store.settings.activeAccent.opacity(0.4) : Color(white: 0.9), lineWidth: 0.5))
                        .clipShape(SachetShape())
                        .rotationEffect(.degrees(sin(Double(i * 5 + 3)) * 2), anchor: .top)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.1)) { selectedDayIndex = sel ? nil : i } }
                    }
                }

                // 时间选择：翻页钟样式，滚轮上下调值
                if selectedDayIndex != nil {
                    HStack(spacing: 2) {
                        Text("时间").font(.system(size: 11, weight: .medium)).foregroundColor(Color(white: 0.5))
                        Spacer()
                        // 小时：滚轮上下调
                        ScrollDigit(value: $selectedHour, range: 0...23, step: 1)
                        Text(":").font(.system(size: 18, weight: .medium, design: .monospaced)).foregroundColor(Color(white: 0.35))
                        // 分钟：滚轮上下调，步进5
                        ScrollDigit(value: $selectedMinute, range: 0...55, step: 5)
                    }
                }

                HStack(spacing: 12) {
                    Text("分类").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    ForEach(TodoColor.allCases, id: \.self) { c in
                        Circle().fill(c.color).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(c == .white ? Color(white: 0.8) : Color.clear, lineWidth: 0.5))
                            .overlay { if c == color { Circle().stroke(Color(white: 0.2), lineWidth: 2.5).frame(width: 30, height: 30) } }
                            .onTapGesture { color = c }
                    }
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("图片").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    Text("您可直接粘贴，粘贴板中的图片会自动填充")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.65))
                    Spacer()
                    Text("\(images.count)/3").font(.system(size: 10, design: .monospaced)).foregroundColor(Color(white: 0.7))
                }
                HStack(spacing: 8) {
                    ForEach(images.indices, id: \.self) { i in
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: images[i]).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48).cornerRadius(8).clipped()
                            Button { images.remove(at: i) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white).shadow(radius: 2)
                            }.buttonStyle(.plain).offset(x: 4, y: -4)
                        }
                    }
                    if images.count < 3 {
                        Button { images.append(contentsOf: store.pickImages(max: 3 - images.count)) } label: {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(Color(white: 0.75)).frame(width: 48, height: 48)
                                .overlay { Text("＋").font(.system(size: 16)).foregroundColor(Color(white: 0.55)) }
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("保存") { save() }.keyboardShortcut(.defaultAction)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(.top, 4)
            }
            .padding(20).frame(width: 340)
            .background(.regularMaterial).cornerRadius(14).shadow(radius: 20)
            .onAppear { setupPasteMonitor() }.onDisappear { removePasteMonitor() }
        }
    }
    @State private var pasteMonitor: Any?
    private func setupPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "v",
               NSPasteboard.general.canReadItem(withDataConformingToTypes: [NSPasteboard.PasteboardType.tiff.rawValue, NSPasteboard.PasteboardType.png.rawValue, "public.image"]) {
                DispatchQueue.main.async { self.pasteFromClipboard() }; return nil
            }; return e
        }
    }
    private func removePasteMonitor() { if let m = pasteMonitor { NSEvent.removeMonitor(m); pasteMonitor = nil } }
    private func pasteFromClipboard() {
        guard images.count < 3 else { return }
        if let img = NSImage(pasteboard: NSPasteboard.general) { images.append(img); return }
        if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: ["public.image"]]) as? [URL] {
            for url in urls.prefix(3 - images.count) { if let img = NSImage(contentsOf: url) { images.append(img) } }
        }
    }
    private func save() {
        let t = text.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        store.addTodo(text: t, color: color, images: images, deadline: computedDeadline); isPresented = false
    }
}

// MARK: - Scroll Digit (翻页钟数字，滚轮上下调值)

struct ScrollDigit: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    @State private var isHovered = false

    private func adjust(_ delta: Int) {
        let new = value + delta
        if new < range.lowerBound { value = range.upperBound + step + new }
        else if new > range.upperBound { value = range.lowerBound }
        else { value = new }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(String(format: "%02d", value))
                .font(.system(size: 20, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.2))
                .frame(width: 36, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(isHovered ? Color(white: 0.92) : Color(white: 0.95)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.88), lineWidth: 0.5))
                .overlay(ScrollWheelCatcher(onChange: { delta in adjust(delta > 0 ? -step : step) }))
                .onHover { isHovered = $0 }
            VStack(spacing: 2) {
                ScrollDigitArrow(systemName: "chevron.up") { adjust(step) }
                ScrollDigitArrow(systemName: "chevron.down") { adjust(-step) }
            }
        }
    }
}

// 上下箭头：方便非触摸板用户点按调值
struct ScrollDigitArrow: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(white: hovered ? 0.25 : 0.45))
                .frame(width: 16, height: 13)
                .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color(white: 0.88) : Color(white: 0.95)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.88), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// 用 overlay 的 NSView 捕获滚轮/触摸板事件（通过 Coordinator 防止野指针崩溃）
struct ScrollWheelCatcher: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ScrollCatcherView {
        let v = ScrollCatcherView()
        v.coordinator = context.coordinator
        context.coordinator.onChange = onChange
        return v
    }

    func updateNSView(_ v: ScrollCatcherView, context: Context) {
        context.coordinator.onChange = onChange
    }

    static func dismantleNSView(_ nsView: ScrollCatcherView, coordinator: Coordinator) {
        nsView.coordinator = nil
        coordinator.onChange = nil
    }

    class Coordinator {
        var onChange: ((CGFloat) -> Void)?
    }
}

final class ScrollCatcherView: NSView {
    weak var coordinator: ScrollWheelCatcher.Coordinator?
    private var accumulated: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
        accumulated += dy
        if abs(accumulated) > 12 {
            coordinator?.onChange?(accumulated)
            accumulated = 0
        }
        if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
            accumulated = 0
        }
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let images: [NSImage]; @Binding var index: Int; let onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.58).onTapGesture { onClose() }
            if !images.isEmpty {
                Image(nsImage: images[index]).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 360, maxHeight: 320).cornerRadius(12).shadow(radius: 16)
                if images.count > 1 {
                    HStack {
                        navBtn("chevron.left") { index = (index - 1 + images.count) % images.count }
                        Spacer()
                        navBtn("chevron.right") { index = (index + 1) % images.count }
                    }.padding(.horizontal, 14)
                }
                VStack {
                    HStack { Spacer(); Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundColor(.white.opacity(0.85))
                    }.buttonStyle(.plain) }
                    Spacer()
                    Text("\(index + 1) / \(images.count)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.3)).cornerRadius(20)
                }.padding(14)
            }
        }
    }
    private func navBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(white: 0.13)).frame(width: 44, height: 44)
                .background(.regularMaterial).clipShape(Circle()).shadow(color: .black.opacity(0.1), radius: 6)
        }.buttonStyle(.plain)
    }
}

// MARK: - Todo Reorder Drop Delegate

struct TodoReorderDelegate: DropDelegate {
    let targetID: UUID
    let store: DataStore
    @Binding var draggingTodoID: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggingTodoID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingTodoID, sourceID != targetID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            store.moveTodo(from: sourceID, to: targetID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}
