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
        // 启动复位:卡在 searching 的、或 done 但结论为空的(无效结果),都回 idle 让定时器重试
        for i in todos.indices {
            let st = todos[i].aiSearchState
            if st == .searching || (st == .done && (todos[i].aiConclusion ?? "").isEmpty) {
                todos[i].aiSearchState = .idle
            }
        }
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

    func addTodo(text: String, color: TodoColor, images: [NSImage], deadline: Date? = nil, aiState: AISearchState = .idle) {
        var names: [String] = []
        for img in images.prefix(3) {
            let name = UUID().uuidString + ".jpg"
            if saveImage(img, name: name) { names.append(name) }
        }
        var todo = Todo(text: text, color: color, imageNames: names, deadline: deadline)
        todo.aiSearchState = aiState
        todos.append(todo)
        save()
    }

    func updateTodo(_ id: UUID, text: String? = nil, color: TodoColor? = nil, deadline: Date?? = nil) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if let t = text {
            // 文本被手动编辑 → 重置 AI 状态重新检索(含被编辑的截图占位/已不采纳项)
            if t != todos[i].text {
                todos[i].aiSearchState = .idle
                todos[i].aiConclusion = nil
                todos[i].aiSource = nil
            }
            todos[i].text = t
        }
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

    // MARK: - AI 连接测试

    /// 用传入的凭证发一个最小请求验证可用性,不依赖已保存的 settings(便于"先测后存")
    func testAIConnection(provider: AIProvider, baseURL: String, apiKey: String, model: String) async -> (ok: Bool, message: String) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let mdl = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !key.isEmpty, !mdl.isEmpty else {
            return (false, "请先填写接口地址、API Key 和模型名")
        }
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base

        let path = provider.isAnthropic ? "/v1/messages" : "/chat/completions"
        guard let url = URL(string: root + path) else {
            return (false, "接口地址格式不正确")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        if provider.isAnthropic {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": mdl, "max_tokens": 1, "messages": [["role": "user", "content": "hi"]]]
        } else {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = ["model": mdl, "max_tokens": 1, "messages": [["role": "user", "content": "hi"]]]
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                return (false, "无响应")
            }
            if (200...299).contains(http.statusCode) {
                return (true, "连接成功，模型 \(mdl) 可用")
            }
            // 把后端错误转成可读提示,不直接抛原始 JSON 给用户
            let detail = Self.parseAPIError(data) ?? "HTTP \(http.statusCode)"
            switch http.statusCode {
            case 401, 403: return (false, "鉴权失败，请检查 API Key（\(detail)）")
            case 404:      return (false, "接口地址或模型名不正确（\(detail)）")
            case 429:      return (false, "请求过于频繁或额度不足（\(detail)）")
            default:       return (false, "连接失败：\(detail)")
            }
        } catch {
            return (false, "网络错误：\(error.localizedDescription)")
        }
    }

    /// 从供应商错误响应里抠出 message 字段(OpenAI/Anthropic 通用结构)
    private static func parseAPIError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
        if let msg = obj["message"] as? String { return msg }
        return nil
    }

    // MARK: - AI 凭证就绪判断

    var aiConfigured: Bool {
        let s = settings
        return !(s.aiAPIKey ?? "").isEmpty && !(s.aiBaseURL ?? "").isEmpty && !(s.aiModelName ?? "").isEmpty
    }

    // MARK: - AI 调用底座

    private func aiEndpoint() -> (url: URL, anthropic: Bool, key: String, model: String)? {
        let s = settings
        guard aiConfigured, let base0 = s.aiBaseURL, let key = s.aiAPIKey, let model = s.aiModelName else { return nil }
        let provider = s.aiProvider
        let base = base0.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        let path = provider.isAnthropic ? "/v1/messages" : "/chat/completions"
        guard let url = URL(string: root + path) else { return nil }
        return (url, provider.isAnthropic, key.trimmingCharacters(in: .whitespacesAndNewlines), model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func buildRequest(_ ep: (url: URL, anthropic: Bool, key: String, model: String), body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: ep.url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if ep.anthropic {
            req.setValue(ep.key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            req.setValue("Bearer \(ep.key)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 解析返回正文(OpenAI choices / Anthropic content 两种结构)
    /// 通用多供应商正文提取。兼容:
    /// - OpenAI 兼容 content 字符串(DeepSeek/Moonshot/OpenAI/智谱普通模型…)
    /// - content 为数组分片(部分代理/供应商)
    /// - 思考模型把可见答案塞 reasoning_content(GLM-4.5+/DeepSeek-R1/Qwen-thinking…)→ 兜底
    /// - Anthropic content blocks
    private static func extractContent(_ data: Data, anthropic: Bool) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func clean(_ s: String?) -> String? {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        if anthropic {
            if let blocks = obj["content"] as? [[String: Any]] {
                let text = blocks.compactMap { $0["text"] as? String }.joined()
                if let c = clean(text) { return c }
            }
            return nil
        }
        guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        let msg = first["message"] as? [String: Any] ?? [:]
        // 1. content 字符串(最常见)
        if let c = clean(msg["content"] as? String) { return c }
        // 2. content 数组分片(content: [{type,text}, ...])
        if let parts = msg["content"] as? [[String: Any]] {
            if let c = clean(parts.compactMap { $0["text"] as? String }.joined()) { return c }
        }
        // 3. 思考模型兜底:可见答案在 reasoning_content
        if let c = clean(msg["reasoning_content"] as? String) { return c }
        // 4. 个别供应商放在 message.text
        if let c = clean(msg["text"] as? String) { return c }
        return nil
    }

    /// 取 finish_reason 用于诊断(length=token 耗尽,stop=正常,等)
    private static func finishReason(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]] else { return nil }
        return choices.first?["finish_reason"] as? String
    }

    /// 纯文本对话(检索用),返回正文或 nil
    private func aiChatText(system: String, user: String, maxTokens: Int) async -> String? {
        guard let ep = aiEndpoint() else {
            applog("✗ aiChatText: endpoint 构建失败(配置不全或 URL 非法)")
            return nil
        }
        applog("→ 请求 \(ep.url.absoluteString) model=\(ep.model)")
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": user],
        ]
        let req = buildRequest(ep, body: ["model": ep.model, "max_tokens": maxTokens, "messages": messages])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                applog("✗ 无 HTTP 响应")
                return nil
            }
            guard (200...299).contains(http.statusCode) else {
                let detail = Self.parseAPIError(data) ?? "HTTP \(http.statusCode)"
                applog("✗ HTTP \(http.statusCode): \(detail)")
                return nil
            }
            guard let content = Self.extractContent(data, anthropic: ep.anthropic) else {
                // 诊断:打印 finish_reason 帮助定位(length=思考耗尽 token / 其它=格式问题)
                applog("✗ HTTP 200 正文为空,finish_reason=\(Self.finishReason(data) ?? "?")")
                return nil
            }
            applog("✓ HTTP 200,正文 \(content.count) 字")
            return content
        } catch {
            applog("✗ 网络错误: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 功能1:截图视觉提取待办

    enum ExtractResult {
        case success([(text: String, deadline: Date?)])
        case visionUnsupported   // 模型不支持视觉 / 接口报错
        case network(String)
    }

    /// 把截图送进视觉模型,提取待办事项+时间
    func extractTodosFromImage(_ image: NSImage) async -> ExtractResult {
        guard let ep = aiEndpoint(), let b64 = Self.jpegBase64(image) else {
            return .visionUnsupported
        }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm EEEE"; df.locale = Locale(identifier: "zh_CN")
        let today = df.string(from: Date())
        let prompt = """
        今天是 \(today)。请从这张图片中提取所有待办事项及其截止时间，以 JSON 数组返回，每个元素格式：{"text":"待办内容","deadline":"yyyy-MM-dd HH:mm" 或 null}。只输出 JSON，不要解释，不要使用 markdown 代码块。
        """

        let body: [String: Any]
        if ep.anthropic {
            body = ["model": ep.model, "max_tokens": 2048, "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": b64]],
                ],
            ]]]
        } else {
            body = ["model": ep.model, "max_tokens": 2048, "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
                ],
            ]]]
        }
        let req = buildRequest(ep, body: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .network("无响应") }
            guard (200...299).contains(http.statusCode) else {
                return .visionUnsupported   // 多为模型不支持图片输入
            }
            guard let content = Self.extractContent(data, anthropic: ep.anthropic) else {
                return .visionUnsupported
            }
            return .success(Self.parseExtractedTodos(content))
        } catch {
            return .network(error.localizedDescription)
        }
    }

    /// 解析模型返回的 JSON 待办数组(容忍 markdown 代码块包裹)
    private static func parseExtractedTodos(_ raw: String) -> [(text: String, deadline: Date?)] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "```") {
            s = String(s[r.upperBound...])
            if s.hasPrefix("json") { s = String(s.dropFirst(4)) }
            if let end = s.range(of: "```") { s = String(s[..<end.lowerBound]) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = s.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"; df.locale = Locale(identifier: "zh_CN")
        return arr.compactMap { item in
            guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            var dl: Date? = nil
            if let ds = item["deadline"] as? String, !ds.isEmpty, ds.lowercased() != "null" {
                dl = df.date(from: ds)
            }
            return (text, dl)
        }
    }

    /// NSImage → JPEG base64(限制最长边以控制请求体积)
    private static func jpegBase64(_ image: NSImage, maxDim: CGFloat = 1280) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        let scale = min(1, maxDim / max(w, h))
        let tw = Int(w * scale), th = Int(h * scale)
        guard tw > 0, th > 0,
              let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
        rep.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = resized.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return nil }
        return jpeg.base64EncodedString()
    }

    /// 截图入口编排:配了模型走视觉提取生成待办;没配则放图+兜底文案
    func addTodosFromScreenshot(_ image: NSImage) async {
        guard aiConfigured else {
            await MainActor.run {
                self.addTodo(text: "自动创建待办，如果您配置了大模型，我会自动为您提取待办事项和时间。", color: .red, images: [image])
            }
            return
        }
        let result = await extractTodosFromImage(image)
        await MainActor.run {
            switch result {
            case .success(let items) where !items.isEmpty:
                for (idx, item) in items.enumerated() {
                    self.addTodo(text: item.text, color: .red, images: idx == 0 ? [image] : [], deadline: item.deadline)
                }
            case .success:
                self.addTodo(text: "未从截图中识别到待办，请手动编辑。", color: .red, images: [image], aiState: .dismissed)
            case .visionUnsupported:
                self.addTodo(text: "您配置的模型不支持视觉，提取信息失败。", color: .red, images: [image], aiState: .dismissed)
            case .network(let msg):
                self.addTodo(text: "网络错误，提取失败：\(msg)", color: .red, images: [image], aiState: .dismissed)
            }
        }
    }

    // MARK: - 功能2:AI 帮手检索(每分钟批量,自身知识作答)

    /// 每批最多挑 limit 条:未完成 + 状态 idle(未检索/未在检索/无结果)
    func runAISearchBatch(limit: Int = 3) {
        guard aiConfigured else {
            applog("批次跳过: 未配置大模型(URL/Key/模型名 有空)")
            return
        }
        let s = settings
        applog("配置: \(s.aiProvider.label) | \(s.aiBaseURL ?? "?") | \(s.aiModelName ?? "?")")
        // 状态分布诊断
        let undone = todos.filter { !$0.isDone }
        let cIdle = undone.filter { $0.aiSearchState == .idle }.count
        let cSearching = undone.filter { $0.aiSearchState == .searching }.count
        let cDone = undone.filter { $0.aiSearchState == .done }.count
        let cDoneEmpty = undone.filter { $0.aiSearchState == .done && ($0.aiConclusion ?? "").isEmpty }.count
        let cFailed = undone.filter { $0.aiSearchState == .failed }.count
        let cSkipped = undone.filter { $0.aiSearchState == .skipped }.count
        let cDismissed = undone.filter { $0.aiSearchState == .dismissed }.count
        applog("状态: 未完成\(undone.count) | idle\(cIdle) searching\(cSearching) done\(cDone)(空\(cDoneEmpty)) failed\(cFailed) 私域\(cSkipped) 不采纳\(cDismissed)")

        // idle(从未检索)和 failed(上次失败)都需要触发;done/searching 跳过(满足不重复触发)
        let needsSearch: (Todo) -> Bool = { !$0.isDone && ($0.aiSearchState == .idle || $0.aiSearchState == .failed) }
        let pending = todos.filter(needsSearch).prefix(limit)
        applog("本批取 \(pending.count) 条")
        for t in pending { startAISearch(t.id) }
    }

    /// 触发单条检索。force=true 时跳过分类直接深度调研(用户手动点灰图标强制检索,可覆盖 skipped 误判)
    func startAISearch(_ id: UUID, force: Bool = false) {
        guard aiConfigured, let i = todos.firstIndex(where: { $0.id == id }) else { return }
        let st = todos[i].aiSearchState
        // 自动触发只认 idle/failed;force 还能从 skipped/dismissed 强制拉起
        guard force || st == .idle || st == .failed else { return }
        guard st != .searching else { return }
        todos[i].aiSearchState = .searching
        save()
        let text = todos[i].text
        applog("\(force ? "强制" : "")开始检索: \(text.prefix(20))")
        Task {
            let outcome = await searchTodoLLM(text, force: force)
            await MainActor.run {
                guard let j = self.todos.firstIndex(where: { $0.id == id }) else { return }
                switch outcome {
                case .research(let conclusion, let source):
                    self.todos[j].aiConclusion = conclusion
                    self.todos[j].aiSource = source
                    self.todos[j].aiSearchState = .done
                    applog("完成(调研): \(text.prefix(12)) → \(conclusion.prefix(20))")
                case .skip:
                    self.todos[j].aiConclusion = nil
                    self.todos[j].aiSource = nil
                    self.todos[j].aiSearchState = .skipped
                    applog("跳过(私域): \(text.prefix(20))")
                case .failed:
                    self.todos[j].aiSearchState = .failed
                    applog("失败: \(text.prefix(20))")
                }
                self.save()
            }
        }
    }

    /// 不采纳:清掉结果,标为 dismissed(终态,批次不再捡,UI 不再显示)
    func dismissAISearch(_ id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        applog("不采纳: \(todos[i].text.prefix(20))")
        todos[i].aiConclusion = nil
        todos[i].aiSource = nil
        todos[i].aiSearchState = .dismissed
        save()
    }

    private enum SearchOutcome { case research(conclusion: String, source: String), skip, failed }

    /// 默认检索提示词(自动模式)。{{todo}} 会被替换成待办内容。用户可在设置里改写。
    static let defaultSearchPrompt = """
    判断下面这条待办：
    - 仅当它是纯私人生活事务（买东西、吃饭、个人提醒、约朋友）或含账号密钥等敏感信息时，回复一个词：SKIP
    - 只要涉及工作、项目、技术、产品、公司、品牌、行业、市场、方案、调研等（即使没有明确的搜索词，也尽量抓取相关产品/公司介绍等公开资料），都给出有数据支撑的结论和参考来源，严格按格式：
    结论：<带数据的结论>
    来源：<参考来源>

    待办：{{todo}}
    """

    private func searchTodoLLM(_ text: String, force: Bool = false) async -> SearchOutcome {
        let system = "你是待办助手,用你已有的知识帮用户做调研,给出有数据支撑的结论。"
        let user: String
        if force {
            // 强制模式:不分类,直接深度调研
            user = """
            针对下面这条待办，用你已有的知识给出有数据支撑的结论和参考来源，严格按格式：
            结论：<带数据的结论>
            来源：<参考来源>

            待办：\(text)
            """
        } else {
            // 自动模式:用用户自定义提示词(没填则用默认),替换 {{todo}}
            var template = (settings.aiSearchPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultSearchPrompt
            if template.contains("{{todo}}") {
                template = template.replacingOccurrences(of: "{{todo}}", with: text)
            } else {
                template += "\n\n待办：\(text)"
            }
            user = template
        }
        // max_tokens 给大:思考模型(GLM-4.5+/DeepSeek-R1 等)会先消耗预算思考,留不够会导致 content 为空
        guard let raw = await aiChatText(system: system, user: user, maxTokens: 3000) else { return .failed }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !force && trimmed.uppercased().hasPrefix("SKIP") {
            return .skip
        }
        let r = Self.parseConclusionSource(raw)
        return .research(conclusion: r.conclusion, source: r.source)
    }

    private static func parseConclusionSource(_ raw: String) -> (conclusion: String, source: String) {
        // 多行累积:遇到「结论」「来源」标记切换归属,后续无标记行归到当前段,避免多行结论被截断只剩首行
        var conclusionLines: [String] = []
        var sourceLines: [String] = []
        enum Section { case none, conclusion, source }
        var current: Section = .none
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if let r = l.range(of: "结论：") ?? l.range(of: "结论:") {
                current = .conclusion
                let rest = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { conclusionLines.append(rest) }
            } else if let r = l.range(of: "来源：") ?? l.range(of: "来源:") {
                current = .source
                let rest = String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { sourceLines.append(rest) }
            } else {
                switch current {
                case .conclusion: conclusionLines.append(l)
                case .source: sourceLines.append(l)
                case .none: break
                }
            }
        }
        var conclusion = conclusionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // 模型没按格式时,整段当结论
        if conclusion.isEmpty && source.isEmpty {
            conclusion = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (conclusion, source)
    }
}
