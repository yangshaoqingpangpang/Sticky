import SwiftUI

// MARK: - Notes Panel (灵感面板)

struct NotesPanel: View {
    @ObservedObject var store: DataStore
    @State private var editingNoteID: UUID?

    var body: some View {
        if let noteID = editingNoteID, let note = store.notes.first(where: { $0.id == noteID }) {
            NoteEditorView(store: store, note: note, onBack: { editingNoteID = nil })
        } else {
            NotesListView(store: store, onSelect: { editingNoteID = $0 })
        }
    }
}

// MARK: - Notes List

struct NotesListView: View {
    @ObservedObject var store: DataStore
    var onSelect: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search + Add
            HStack(spacing: 8) {
                Spacer()
                Button {
                    let id = store.addNote()
                    onSelect(id)
                } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36)
                        .background(store.settings.activeAccent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 6)

            if store.notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 28))
                        .foregroundColor(.nuOutlineVariant)
                    Text("点击 ＋ 记录灵感")
                        .font(.system(size: 13))
                        .foregroundColor(.nuOutline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.notes) { note in
                            NoteRow(note: note, store: store, onSelect: onSelect)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note
    @ObservedObject var store: DataStore
    var onSelect: (UUID) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 左侧主题色条
            RoundedRectangle(cornerRadius: 2)
                .fill(store.settings.activeAccent)
                .frame(width: 3, height: 30)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(note.title.isEmpty ? "未命名笔记" : note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.nuOnSurface)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(note.content.count)字")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.nuOutline)
                }

                if !note.content.isEmpty {
                    Text(note.content)
                        .font(.system(size: 11.5))
                        .foregroundColor(.nuOnSurfaceVariant)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(relativeTime(note.updatedAt))
                        .font(.system(size: 10.5))
                        .foregroundColor(.nuOutline)
                        .monospacedDigit()
                    Spacer()
                    // 淡淡的删除错号
                    Button { store.deleteNote(note.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.nuOutline)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 0.9 : 0.35)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.nuGray6.opacity(0.6) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.nuOutlineVariant.opacity(0.5), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(note.id) }
        .onHover { isHovered = $0 }
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
}

// MARK: - Note Editor

struct NoteEditorView: View {
    @ObservedObject var store: DataStore
    let note: Note
    var onBack: () -> Void
    @State private var title: String
    @State private var content: String
    @FocusState private var contentFocused: Bool

    init(store: DataStore, note: Note, onBack: @escaping () -> Void) {
        self.store = store; self.note = note; self.onBack = onBack
        _title = State(initialValue: note.title)
        _content = State(initialValue: note.content)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack(spacing: 8) {
                Button {
                    saveAndBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(store.settings.activeAccentDeep)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(content.count)字")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.nuOutline)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Rectangle().fill(Color.nuOutlineVariant.opacity(0.4)).frame(height: 0.5).padding(.horizontal, 16)

            // Title（带浅色标注）
            VStack(alignment: .leading, spacing: 3) {
                Text("标题")
                    .font(.system(size: 10, weight: .medium)).tracking(0.5)
                    .foregroundColor(.nuOutline)
                TextField("输入标题…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.nuOnSurface)
                    .onChange(of: title) { _, newVal in
                        store.updateNote(note.id, title: newVal)
                    }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            // 题目 / 内容 分隔线
            Rectangle().fill(Color.nuOutlineVariant.opacity(0.4)).frame(height: 0.5).padding(.horizontal, 16)

            // 正文标注
            HStack {
                Text("正文")
                    .font(.system(size: 10, weight: .medium)).tracking(0.5)
                    .foregroundColor(.nuOutline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)

            // Content editor
            ScrollView {
                NoteTextEditor(text: $content)
                    .padding(.horizontal, 18)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .onChange(of: content) { _, newVal in
                        store.updateNote(note.id, content: newVal)
                    }
            }
        }
    }

    private func saveAndBack() {
        store.updateNote(note.id, title: title, content: content)
        onBack()
    }
}

// MARK: - NSTextView wrapper for multi-line editing

struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 13.5)
        textView.textColor = NSColor(white: 0.2, alpha: 1)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

