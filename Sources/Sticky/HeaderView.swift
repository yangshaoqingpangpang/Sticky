import SwiftUI

struct HeaderView: View {
    @ObservedObject var store: DataStore
    var onSettings: () -> Void = {}
    var onShowLog: () -> Void = {}
    @State private var now = Date()
    @State private var timeTapCount = 0
    @State private var timeTapResetWork: DispatchWorkItem?
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var isSmall: Bool { store.settings.sizeMode == .small }

    var body: some View {
        Group {
            if isSmall { smallHeader } else { largeHeader }
        }
        .padding(.horizontal, 16).padding(.top, isSmall ? 8 : 14).padding(.bottom, isSmall ? 8 : 16)
        .onReceive(timer) { now = $0 }
    }

    // 大尺寸:日期+工作日(加粗左侧)、纪念日、时间 同一行,纵向居中对齐
    private var largeHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateStrCompact)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.nuOnSurface)
                .fixedSize()
                .contentShape(Rectangle())
                .onTapGesture { onSettings() }
            Spacer(minLength: 6)
            anniversaryRow
            timeChip.fixedSize()
        }
    }

    // 小尺寸:日期 + 纪念日 + 时间 同一行
    private var smallHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateStrCompact)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.nuOnSurface)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { onSettings() }
            Spacer(minLength: 4)
            anniversaryRow
            timeChip
        }
        .padding(.top, 2)
    }

    // 时间:小字 + 时钟图标(对齐设计稿),连点 5 次出日志
    private var timeChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 10.5))
                .foregroundColor(.nuOutline)
            Text(timeStr)
                .font(.system(size: isSmall ? 12 : 13, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.nuOnSurfaceVariant)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTimeTap() }
    }

    @ViewBuilder private var anniversaryRow: some View {
        HStack(spacing: 8) {
            if let (anniv, days) = store.nearestAnniversary() {
                Text(days == 0 ? "今天 · \(anniv.name)" : "距\(anniv.name) \(days) 天")
                    .font(.system(size: isSmall ? 10.5 : 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.nuOnSurfaceVariant)
                    .lineLimit(1)
                    .padding(.horizontal, isSmall ? 8 : 10).padding(.vertical, 3)
                    .background(Color.nuGray6)
                    .overlay(Capsule().stroke(Color.nuOutlineVariant.opacity(0.4), lineWidth: 0.5))
                    .clipShape(Capsule())
            }
            if !isSmall, store.nearestAnniversary() != nil, SolarTerms.current() != nil {
                Circle().fill(store.settings.activeAccentDeep).frame(width: 3, height: 3).opacity(0.7)
            }
            if !isSmall, let term = SolarTerms.current() {
                Text(term)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(store.settings.activeAccentDeep)
            }
        }
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
    private var dateStrCompact: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEE"; return f.string(from: now)
    }
}

