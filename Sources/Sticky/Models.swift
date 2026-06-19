import SwiftUI

// MARK: - Native Utility 配色（表面/语义色，accent 仍走主题色 activeAccent，不在此）

extension Color {
    static let nuSurface          = Color(red: 0.976, green: 0.976, blue: 1.0)    // #f9f9ff 面板底
    static let nuGray6            = Color(red: 0.949, green: 0.949, blue: 0.969)  // #F2F2F7 搜索/hover/badge
    static let nuOutline          = Color(red: 0.443, green: 0.467, blue: 0.525)  // #717786 次要文字/图标
    static let nuOutlineVariant   = Color(red: 0.757, green: 0.776, blue: 0.843)  // #c1c6d7 边框/分隔线
    static let nuOnSurface        = Color(red: 0.094, green: 0.110, blue: 0.137)  // #181c23 主文字
    static let nuOnSurfaceVariant = Color(red: 0.255, green: 0.278, blue: 0.333)  // #414755 副文字
    static let nuRed              = Color(red: 1.0,   green: 0.231, blue: 0.188)  // #FF3B30 死线/危险
    static let nuDeadlineBg       = Color(red: 1.0,   green: 0.949, blue: 0.949)  // #FFF2F2 死线整行底
    static let nuGreen            = Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759 成功
}

// MARK: - Todo

enum AISearchState: String, Codable {
    case idle, searching, done, failed
    case skipped     // 私域/个人事务,模型判定无需建议
    case dismissed   // 用户主动不采纳,不再显示也不再检索
}

struct Todo: Identifiable, Codable {
    var id = UUID()
    var text: String
    var color: TodoColor = .red
    var imageNames: [String] = []
    var isDone = false
    var createdAt = Date()
    var completedAt: Date?
    var deadline: Date?
    var isSuperDeadline = false
    // AI 帮手检索结果
    var aiConclusion: String?
    var aiSource: String?
    var aiSearchStateRaw: String?

    var aiSearchState: AISearchState {
        get { AISearchState(rawValue: aiSearchStateRaw ?? "") ?? .idle }
        set { aiSearchStateRaw = newValue.rawValue }
    }

    init(text: String, color: TodoColor = .red, imageNames: [String] = [], isDone: Bool = false,
         createdAt: Date = Date(), completedAt: Date? = nil, deadline: Date? = nil, isSuperDeadline: Bool = false) {
        self.text = text; self.color = color; self.imageNames = imageNames; self.isDone = isDone
        self.createdAt = createdAt; self.completedAt = completedAt; self.deadline = deadline; self.isSuperDeadline = isSuperDeadline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        color = try c.decodeIfPresent(TodoColor.self, forKey: .color) ?? .red
        imageNames = try c.decodeIfPresent([String].self, forKey: .imageNames) ?? []
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        isSuperDeadline = try c.decodeIfPresent(Bool.self, forKey: .isSuperDeadline) ?? false
        aiConclusion = try c.decodeIfPresent(String.self, forKey: .aiConclusion)
        aiSource = try c.decodeIfPresent(String.self, forKey: .aiSource)
        aiSearchStateRaw = try c.decodeIfPresent(String.self, forKey: .aiSearchStateRaw)
    }
}

/// 四色：紧急红、不紧急绿、重要灰、不重要白
enum TodoColor: String, Codable, CaseIterable {
    case red, green, gray, white

    var color: Color {
        switch self {
        case .red:   return Color(red: 0.85, green: 0.45, blue: 0.38)
        case .green: return Color(red: 0.50, green: 0.75, blue: 0.50)
        case .gray:  return Color(white: 0.44)
        case .white: return Color(white: 0.92)
        }
    }
}

// MARK: - Snippet

struct Snippet: Identifiable, Codable {
    var id = UUID()
    var text: String
}

// MARK: - Note (灵感笔记)

struct Note: Identifiable, Codable {
    var id = UUID()
    var title: String
    var content: String
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String = "未命名笔记", content: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.title = title; self.content = content; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decode(String.self, forKey: .title)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Anniversary

struct Anniversary: Identifiable, Codable {
    var id = UUID()
    var month: Int
    var day: Int
    var name: String
}

// MARK: - Settings

struct AppSettings: Codable {
    var theme: AppTheme = .macaronCyan
    var screenshotShortcut = "⌘⇧S"
    var reminderDays: [Int] = [1, 3, 7]
    // 自定义颜色 (RGB 0~1)
    var customColorR: Double?
    var customColorG: Double?
    var customColorB: Double?
    var useCustomColor: Bool = false
    // 窗口尺寸档:大(默认) / 小. 用 raw 形式存以兼容旧 data.json
    var sizeModeRaw: String?
    // AI 配置:供应商 / 接口地址 / 密钥 / 模型名. 全 optional 兼容旧 data.json
    var aiProviderRaw: String?
    var aiBaseURL: String?
    var aiAPIKey: String?
    var aiModelName: String?
    var aiSearchPrompt: String?   // AI 帮手检索提示词(自定义,nil=用默认)
}

enum SizeMode: String, Codable, CaseIterable {
    case large, small
}

// MARK: - AI Provider

enum AIProvider: String, Codable, CaseIterable {
    case deepseek, zhipu, qwen, moonshot, openai, claude, custom

    var label: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .zhipu:    return "智谱 GLM"
        case .qwen:     return "通义千问"
        case .moonshot: return "Moonshot Kimi"
        case .openai:   return "OpenAI"
        case .claude:   return "Claude"
        case .custom:   return "自定义"
        }
    }

    /// 默认接口地址(base url,不含具体 path)
    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .zhipu:    return "https://open.bigmodel.cn/api/paas/v4"
        case .qwen:     return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .moonshot: return "https://api.moonshot.cn/v1"
        case .openai:   return "https://api.openai.com/v1"
        case .claude:   return "https://api.anthropic.com"
        case .custom:   return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-chat"
        case .zhipu:    return "glm-4"
        case .qwen:     return "qwen-plus"
        case .moonshot: return "moonshot-v1-8k"
        case .openai:   return "gpt-4o"
        case .claude:   return "claude-3-5-sonnet-20241022"
        case .custom:   return ""
        }
    }

    /// Anthropic 用独立的 /v1/messages 协议;其余走 OpenAI 兼容 /chat/completions
    var isAnthropic: Bool { self == .claude }
}

extension AppSettings {
    var customColor: Color? {
        guard let r = customColorR, let g = customColorG, let b = customColorB else { return nil }
        return Color(red: r, green: g, blue: b)
    }

    /// 窗口尺寸档
    var sizeMode: SizeMode {
        get { SizeMode(rawValue: sizeModeRaw ?? "") ?? .large }
        set { sizeModeRaw = newValue.rawValue }
    }

    /// AI 供应商
    var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw ?? "") ?? .deepseek }
        set { aiProviderRaw = newValue.rawValue }
    }

    /// 当前生效的主色
    var activeAccent: Color { useCustomColor ? (customColor ?? AppTheme.macaronCyan.accent) : theme.accent }
    var activeAccentDeep: Color {
        guard useCustomColor, let r = customColorR, let g = customColorG, let b = customColorB else { return theme.accentDeep }
        return Color(red: max(r - 0.15, 0), green: max(g - 0.15, 0), blue: max(b - 0.15, 0))
    }
    var activeSwatch: Color {
        guard useCustomColor, let r = customColorR, let g = customColorG, let b = customColorB else { return theme.swatch }
        return Color(red: min(r * 0.3 + 0.7, 1), green: min(g * 0.3 + 0.7, 1), blue: min(b * 0.3 + 0.7, 1))
    }
}

// MARK: - Theme

enum AppTheme: String, Codable, CaseIterable {
    case macaronCyan, macaronPurple, appleSilver, mintGreen, vibrantOrange

    var accent: Color {
        switch self {
        case .macaronCyan:   return Color(red: 0.35, green: 0.78, blue: 0.74)
        case .macaronPurple: return Color(red: 0.71, green: 0.54, blue: 0.85)
        case .appleSilver:   return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .mintGreen:     return Color(red: 0.42, green: 0.79, blue: 0.56)
        case .vibrantOrange: return Color(red: 0.96, green: 0.55, blue: 0.08)
        }
    }
    var accentDeep: Color {
        switch self {
        case .macaronCyan:   return Color(red: 0.20, green: 0.66, blue: 0.62)
        case .macaronPurple: return Color(red: 0.56, green: 0.37, blue: 0.75)
        case .appleSilver:   return Color(red: 0.43, green: 0.43, blue: 0.45)
        case .mintGreen:     return Color(red: 0.27, green: 0.65, blue: 0.34)
        case .vibrantOrange: return Color(red: 0.85, green: 0.42, blue: 0.0)
        }
    }
    var swatch: Color {
        switch self {
        case .macaronCyan:   return Color(red: 0.78, green: 0.90, blue: 0.88)
        case .macaronPurple: return Color(red: 0.85, green: 0.78, blue: 0.90)
        case .appleSilver:   return Color(red: 0.86, green: 0.86, blue: 0.88)
        case .mintGreen:     return Color(red: 0.78, green: 0.90, blue: 0.82)
        case .vibrantOrange: return Color(red: 0.99, green: 0.90, blue: 0.72)
        }
    }
    var label: String {
        switch self {
        case .macaronCyan:   return "马卡龙青"
        case .macaronPurple: return "马卡龙紫"
        case .appleSilver:   return "苹果银"
        case .mintGreen:     return "薄荷绿"
        case .vibrantOrange: return "活力橙"
        }
    }
}

// MARK: - Solar Terms

enum SolarTerms {
    private static let data: [(Int, Int, String)] = [
        (1,6,"小寒"),(1,20,"大寒"),(2,4,"立春"),(2,19,"雨水"),
        (3,6,"惊蛰"),(3,21,"春分"),(4,5,"清明"),(4,20,"谷雨"),
        (5,6,"立夏"),(5,21,"小满"),(6,6,"芒种"),(6,21,"夏至"),
        (7,7,"小暑"),(7,23,"大暑"),(8,7,"立秋"),(8,23,"处暑"),
        (9,8,"白露"),(9,23,"秋分"),(10,8,"寒露"),(10,23,"霜降"),
        (11,7,"立冬"),(11,22,"小雪"),(12,7,"大雪"),(12,22,"冬至"),
    ]
    /// 只在节气当天显示
    static func current() -> String? {
        let cal = Calendar.current, now = Date()
        let m = cal.component(.month, from: now), d = cal.component(.day, from: now)
        return data.first(where: { $0.0 == m && $0.1 == d })?.2
    }
}
