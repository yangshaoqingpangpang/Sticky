import SwiftUI

struct HeaderView: View {
    @ObservedObject var store: DataStore
    var onSettings: () -> Void = {}
    var onShowLog: () -> Void = {}
    @State private var now = Date()
    @State private var timeTapCount = 0
    @State private var timeTapResetWork: DispatchWorkItem?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Time — 48px, medium weight, tabular nums
            Text(timeStr)
                .font(.system(size: 48, weight: .medium))
                .monospacedDigit()
                .tracking(-1.5)
                .foregroundColor(Color(white: 0.13))
                .contentShape(Rectangle())
                .onTapGesture { handleTimeTap() }

            // Date row — 整行点击进入设置页(与右上角齿轮等价的快捷入口)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                // Date button
                HStack(spacing: 6) {
                    Text(dateStr)
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.42))
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.42))
                        .opacity(0.5)
                }
                .padding(.vertical, 3).padding(.horizontal, 7)
                .cornerRadius(6)

                Spacer(minLength: 8)

                // Holiday section
                HStack(spacing: 8) {
                    if let (anniv, days) = store.nearestAnniversary() {
                        Text(days == 0 ? "今天 · \(anniv.name)" : "距\(anniv.name) \(days) 天")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(Color(white: 0.42))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color(white: 0.96))
                            .overlay(RoundedRectangle(cornerRadius: 99).stroke(Color(white: 0.91), lineWidth: 0.5))
                            .cornerRadius(99)
                    }

                    if store.nearestAnniversary() != nil, SolarTerms.current() != nil {
                        Circle().fill(store.settings.activeAccentDeep).frame(width: 3, height: 3).opacity(0.7)
                    }

                    if let term = SolarTerms.current() {
                        Text(term)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(store.settings.activeAccentDeep)
                    }
                }
            }
            .padding(.top, 10)
            .contentShape(Rectangle())
            .onTapGesture { onSettings() }
        }
        .padding(.horizontal, 22).padding(.bottom, 16)
        .onReceive(timer) { now = $0 }
    }

    /// 连续点击时间 5 次(每次间隔 <1.2s)触发隐藏日志面板
    private func handleTimeTap() {
        timeTapCount += 1
        timeTapResetWork?.cancel()
        if timeTapCount >= 5 {
            timeTapCount = 0
            onShowLog()
            return
        }
        let work = DispatchWorkItem { timeTapCount = 0 }
        timeTapResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private var timeStr: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: now)
    }
    private var dateStr: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 · EEE"; return f.string(from: now)
    }
}

