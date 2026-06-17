import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class DataStore: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var anniversaries: [Anniversary] = []
    @Published var snippets: [Snippet] = []
    @Published var notes: [Note] = []
    @Published var settings: AppSettings = AppSettings()

    private let dataURL: URL
    private let imagesDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = support.appendingPathComponent("Sticky", isDirectory: true)
        imagesDir = appDir.appendingPathComponent("Images", isDirectory: true)
        dataURL = appDir.appendingPathComponent("data.json")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var todos: [Todo]
        var anniversaries: [Anniversary]
        var snippets: [Snippet]
        var notes: [Note]?
        var settings: AppSettings
    }

    func load() {
        guard let data = try? Data(contentsOf: dataURL),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else {
            // 首次启动：预置示例数据
            seedSampleData()
            return
        }
        todos = s.todos; anniversaries = s.anniversaries; snippets = s.snippets; notes = s.notes ?? []; settings = s.settings
    }

    func save() {
        guard let json = try? JSONEncoder().encode(
            Saved(todos: todos, anniversaries: anniversaries, snippets: snippets, notes: notes, settings: settings)
        ) else { return }
        try? json.write(to: dataURL)
    }

    private func seedSampleData() {
        todos = [
            Todo(text: "回复 Alex 关于 Q2 roadmap 的邮件", color: .red, createdAt: Date().addingTimeInterval(-3600)),
            Todo(text: "审阅便笺面板的微交互稿", color: .red, createdAt: Date().addingTimeInterval(-7200)),
            Todo(text: "把周会纪要同步到共享文档", color: .green, createdAt: Date().addingTimeInterval(-10800)),
            Todo(text: "给设计 review 发起一轮时间收集", color: .gray, createdAt: Date().addingTimeInterval(-14400)),
            Todo(text: "续订桌面壁纸订阅", color: .white, createdAt: Date().addingTimeInterval(-86400)),
            Todo(text: "整理读书笔记 · Designing Data-Intensive", color: .green, isDone: true, createdAt: Date().addingTimeInterval(-172800), completedAt: Date().addingTimeInterval(-3600)),
            Todo(text: "给小 A 发生日祝福（自动纪念日）", color: .red, createdAt: Date().addingTimeInterval(-259200)),
            Todo(text: "跑步 · 5km", color: .white, createdAt: Date().addingTimeInterval(-1800)),
        ]
        snippets = [
            Snippet(text: "git commit -m \"feat: \" --signoff"),
            Snippet(text: "ssh -i ~/.ssh/id_ed25519 user@host"),
            Snippet(text: "Best regards,\n— Sent from 便笺"),
            Snippet(text: "⌘⇧4 · 区域截图到便笺"),
        ]
        anniversaries = [
            Anniversary(month: 5, day: 25, name: "结婚纪念日"),
        ]
        save()
    }

    // MARK: Todos

    func addTodo(text: String, color: TodoColor, images: [NSImage], deadline: Date? = nil) {
        var names: [String] = []
        for img in images.prefix(3) {
            let name = UUID().uuidString + ".jpg"
            if saveImage(img, name: name) { names.append(name) }
        }
        todos.append(Todo(text: text, color: color, imageNames: names, deadline: deadline))
        save()
    }

    func updateTodo(_ id: UUID, text: String? = nil, color: TodoColor? = nil, deadline: Date?? = nil) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if let t = text { todos[i].text = t }
        if let c = color { todos[i].color = c }
        if let d = deadline { todos[i].deadline = d }
        save()
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
        save()
    }

    func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isDone.toggle()
        todos[i].completedAt = todos[i].isDone ? Date() : nil
        if todos[i].isDone { todos[i].isSuperDeadline = false }
        save()
    }

    func toggleSuperDeadline(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isSuperDeadline.toggle()
        save()
    }

    func sortTodos() {
        let now = Date()
        todos.sort { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isDone && b.isDone { return (a.completedAt ?? .distantPast) > (b.completedAt ?? .distantPast) }
            let ao = isOverdue(a, now: now), bo = isOverdue(b, now: now)
            if ao != bo { return ao }
            return a.createdAt < b.createdAt
        }
        save()
    }

    func isOverdue(_ todo: Todo, now: Date = Date()) -> Bool {
        guard !todo.isDone, let deadline = todo.deadline else { return false }
        return deadline < now
    }

    func moveTodo(from sourceID: UUID, to targetID: UUID) {
        guard let si = todos.firstIndex(where: { $0.id == sourceID }),
              let ti = todos.firstIndex(where: { $0.id == targetID }),
              si != ti else { return }
        let item = todos.remove(at: si)
        todos.insert(item, at: ti)
        save()
    }

    // MARK: Snippets

    func addSnippet(text: String) {
        snippets.append(Snippet(text: text))
        save()
    }

    func updateSnippet(_ id: UUID, text: String) {
        guard let i = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[i].text = text
        save()
    }

    func deleteSnippet(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    // MARK: Notes

    func addNote(title: String = "未命名笔记") -> UUID {
        let note = Note(title: title)
        notes.insert(note, at: 0)
        save()
        return note.id
    }

    func updateNote(_ id: UUID, title: String? = nil, content: String? = nil) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        if let t = title { notes[i].title = t }
        if let c = content { notes[i].content = c }
        notes[i].updatedAt = Date()
        save()
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        save()
    }

    // MARK: Anniversaries

    func addAnniversary(month: Int, day: Int, name: String) {
        anniversaries.append(Anniversary(month: month, day: day, name: name))
        save()
    }

    func deleteAnniversary(_ id: UUID) {
        anniversaries.removeAll { $0.id == id }
        save()
    }

    func nearestAnniversary() -> (Anniversary, Int)? {
        anniversaries.map { ($0, daysUntil(month: $0.month, day: $0.day)) }.min(by: { $0.1 < $1.1 })
    }

    func daysUntil(month: Int, day: Int) -> Int {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        var c = DateComponents(year: cal.component(.year, from: today), month: month, day: day)
        if let t = cal.date(from: c), t >= today { return cal.dateComponents([.day], from: today, to: t).day ?? 999 }
        c.year! += 1
        guard let t = cal.date(from: c) else { return 999 }
        return cal.dateComponents([.day], from: today, to: t).day ?? 999
    }

    // MARK: Images

    func saveImage(_ image: NSImage, name: String) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return false }
        return (try? data.write(to: imagesDir.appendingPathComponent(name))) != nil
    }

    func loadImage(name: String) -> NSImage? {
        NSImage(contentsOf: imagesDir.appendingPathComponent(name))
    }

    func pickImages(max: Int) -> [NSImage] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.prefix(max).compactMap { NSImage(contentsOf: $0) }
    }

    // MARK: - 备份 / 恢复

    private struct Backup: Codable {
        var version: Int
        var todos: [Todo]
        var anniversaries: [Anniversary]
        var snippets: [Snippet]
        var notes: [Note]
        var settings: AppSettings
        var images: [String: String]   // 文件名 -> base64
    }

    /// 导出全部数据（含图片）到用户选择的位置，默认桌面
    func exportBackup() -> (ok: Bool, message: String) {
        var imgs: [String: String] = [:]
        for name in Set(todos.flatMap { $0.imageNames }) {
            if let d = try? Data(contentsOf: imagesDir.appendingPathComponent(name)) {
                imgs[name] = d.base64EncodedString()
            }
        }
        let backup = Backup(version: 1, todos: todos, anniversaries: anniversaries,
                            snippets: snippets, notes: notes, settings: settings, images: imgs)
        guard let data = try? JSONEncoder().encode(backup) else {
            return (false, "数据编码失败")
        }
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmm"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "便笺备份-\(df.string(from: Date())).json"
        panel.directoryURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Desktop")
        guard panel.runModal() == .OK, let url = panel.url else { return (false, "已取消") }
        do {
            try data.write(to: url)
            return (true, "已备份到「\(url.lastPathComponent)」")
        } catch {
            return (false, "写入失败：\(error.localizedDescription)")
        }
    }

    /// 从用户选择的备份文件导入，覆盖当前全部数据
    func importBackup() -> (ok: Bool, message: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Users/\(NSUserName())/Desktop")
        guard panel.runModal() == .OK, let url = panel.url else { return (false, "已取消") }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            return (false, "文件无法解析，请选择正确的备份文件")
        }
        for (name, b64) in backup.images {
            if let d = Data(base64Encoded: b64) {
                try? d.write(to: imagesDir.appendingPathComponent(name))
            }
        }
        todos = backup.todos
        anniversaries = backup.anniversaries
        snippets = backup.snippets
        notes = backup.notes
        settings = backup.settings
        save()
        return (true, "已导入 \(backup.todos.count) 条待办、\(backup.snippets.count) 条片段")
    }
}
