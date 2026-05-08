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
                    Text("＋").font(.system(size: 15, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(store.settings.activeAccent.opacity(0.08))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22).padding(.bottom, 6)

            if store.notes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 28))
                        .foregroundColor(Color(white: 0.75))
                    Text("点击 ＋ 记录灵感")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.notes) { note in
                            NoteRow(note: note, store: store, onSelect: onSelect)
                            if note.id != store.notes.last?.id {
                                Rectangle().fill(Color(white: 0.93)).frame(height: 0.5)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 4)
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
            // 色点
            RoundedRectangle(cornerRadius: 2)
                .fill(store.settings.activeAccent.opacity(0.5))
                .frame(width: 4, height: 32)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "未命名笔记" : note.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.13))
                    .lineLimit(1)

                if !note.content.isEmpty {
                    Text(note.content)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(white: 0.5))
                        .lineLimit(2)
                }

                Text(relativeTime(note.updatedAt))
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(white: 0.65))
                    .monospacedDigit()
            }

            Spacer(minLength: 4)

            // 字数
            Text("\(note.content.count)字")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.7))
                .padding(.top, 6)
        }
        .padding(.vertical, 9).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color(white: 0.97) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(note.id) }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("删除", role: .destructive) { store.deleteNote(note.id) }
        }
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
                    .foregroundColor(Color(white: 0.65))
            }
            .padding(.horizontal, 22).padding(.vertical, 8)

            Rectangle().fill(Color(white: 0.92)).frame(height: 0.5).padding(.horizontal, 20)

            // Title
            TextField("标题", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(white: 0.13))
                .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 4)
                .onChange(of: title) { _, newVal in
                    store.updateNote(note.id, title: newVal)
                }

            // Content editor
            ScrollView {
                NoteTextEditor(text: $content)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
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

