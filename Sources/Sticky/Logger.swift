import SwiftUI

// MARK: - 隐藏日志模块(连续点击时间 5 次触发,只留最近 200 条)

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let message: String
}

final class AppLog: ObservableObject {
    static let shared = AppLog()
    private let maxEntries = 200

    @Published private(set) var entries: [LogEntry] = []

    func log(_ message: String) {
        let entry = LogEntry(time: Date(), message: message)
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() { entries.removeAll() }

    /// 全部日志拼成纯文本(用于复制)
    var plainText: String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return entries.map { "[\(df.string(from: $0.time))] \($0.message)" }.joined(separator: "\n")
    }
}

/// 全局快捷函数
func applog(_ message: String) { AppLog.shared.log(message) }

// MARK: - 日志面板

struct LogPanel: View {
    @ObservedObject var log = AppLog.shared
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日志").font(.system(size: 14, weight: .semibold))
                Text("最近 \(log.entries.count) 条")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.plainText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 12))
                }.buttonStyle(.plain).help("复制全部")
                Button { log.clear() } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }.buttonStyle(.plain).help("清空")
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                }.buttonStyle(.plain).help("关闭")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            if log.entries.isEmpty {
                Spacer()
                Text("暂无日志").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(log.entries) { e in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(timeStr(e.time))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(e.message)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(Color(white: 0.2))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(e.id)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .onChange(of: log.entries.count) { _ in
                        if let last = log.entries.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
        }
        .background(.background)
    }

    private func timeStr(_ d: Date) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"; return df.string(from: d)
    }
}
