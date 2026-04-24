import SwiftUI
import AppKit

enum PanelPage { case main, anniversary, settings }

struct ContentView: View {
    @ObservedObject var store: DataStore
    @State private var page: PanelPage = .main
    @State private var searchText = ""
    @State private var showNewTodo = false

    var body: some View {
        ZStack {
            // 主题背景色调（铺满整个面板）
            store.settings.activeSwatch.opacity(0.35)
                .ignoresSafeArea()

            mainPage.opacity(page == .main ? 1 : 0)
            if page == .settings {
                SettingsView(store: store, page: $page).transition(.move(edge: .trailing))
            }
            if showNewTodo {
                NewTodoOverlay(store: store, isPresented: $showNewTodo).transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35), value: page)
        .animation(.easeOut(duration: 0.2), value: showNewTodo)
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            ZStack {
                // 拖拽指示条（居中，整个区域可拖拽）
                VStack(spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(white: 0.74))
                        .frame(width: 32, height: 2.5)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(white: 0.80))
                        .frame(width: 32, height: 2.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(WindowDragHandle())

                // 按钮（右上角，浮在拖拽区域上方）
                HStack(spacing: 12) {
                    Spacer()
                    Button { AppDelegate.shared?.startScreenCapture() } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.65))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { page = .settings } } label: {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(white: 0.65))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 22)
            }
            .frame(height: 24)
            .padding(.top, 14)

            // Header
            HeaderView(store: store)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { page = .settings } }

            // Separator
            Rectangle().fill(Color(white: 0.92)).frame(height: 0.5).padding(.horizontal, 20)

            // Section label
            HStack {
                Text("待办事项")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                Spacer()
                Text("· \(filteredTodos.count)")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundColor(Color(white: 0.6))
            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 8)

            // Search bar
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.6))
                    TextField("搜索待办、片段…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(white: 0.97))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.92), lineWidth: 0.5))
                .cornerRadius(12)

                Button { showNewTodo = true } label: {
                    Text("＋").font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(store.settings.activeAccent.opacity(0.08))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.bottom, 2)

            // Todo list (flex area)
            TodoListView(store: store, todos: filteredTodos)

            // Quick copy tray
            VStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.92)).frame(height: 0.5)
                SnippetSection(store: store)
            }
            .background(Color(white: 0.98).opacity(0.65))
        }
    }

    var filteredTodos: [Todo] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? store.todos : store.todos.filter { $0.text.lowercased().contains(q) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("常用片段")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color(white: 0.6))
                Spacer()
                Text("点击复制 · 双击编辑")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(white: 0.75))
            }
            .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 2)

            // List
            if store.snippets.isEmpty && !showAdd {
                Text("暂无片段")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.7))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                let scrollable = store.snippets.count > 5
                Group {
                    if scrollable { ScrollView { list }.frame(maxHeight: 160) }
                    else { list }
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
                        Image(systemName: "plus").font(.system(size: 10))
                        Text("添加片段").font(.system(size: 11))
                    }
                    .foregroundColor(Color(white: 0.55))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22).padding(.top, 4)
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
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(white: 0.42))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(copiedId == s.id ? "已复制 ✓" : "")
                            .font(.system(size: 10.5))
                            .foregroundColor(store.settings.activeAccentDeep)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(copiedId == s.id ? Color(white: 0.95) : Color.clear)
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

