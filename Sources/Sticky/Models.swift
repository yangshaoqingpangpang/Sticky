import SwiftUI

// MARK: - Todo

struct Todo: Identifiable, Codable {
    var id = UUID()
    var text: String
    var color: TodoColor = .red
    var imageNames: [String] = []
    var isDone = false
    var createdAt = Date()
    var completedAt: Date?
    var deadline: Date?
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
}

extension AppSettings {
    var customColor: Color? {
        guard let r = customColorR, let g = customColorG, let b = customColorB else { return nil }
        return Color(red: r, green: g, blue: b)
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
