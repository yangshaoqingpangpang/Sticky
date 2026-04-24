import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: DataStore
    @Binding var page: PanelPage
    @State private var colorPanelObserver: Any?

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider().padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    themeSection
                    sectionDivider
                    // 纪念日日历直接嵌入
                    sectionLabel("纪念日").padding(.bottom, 6)
                    EmbeddedCalendar(store: store)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
        }
        .background(.background)
    }

    private var sectionDivider: some View {
        Rectangle().fill(Color(white: 0.9)).frame(height: 0.5).padding(.vertical, 16)
    }

    private var settingsHeader: some View {
        HStack {
            Button { withAnimation { page = .main } } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left").font(.system(size: 12))
                    Text("返回")
                }.font(.system(size: 13)).foregroundColor(store.settings.activeAccent)
            }.buttonStyle(.plain)
            Text("设置").font(.system(size: 17, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("主题颜色")
                Spacer()
                Text("双击修改自定义颜色").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            // 5预设 + 1自定义 并排
            HStack(spacing: 0) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    themeButton(theme)
                    Spacer()
                }
                // 第6个：自定义
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(store.settings.customColor ?? Color(white: 0.92))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(store.settings.useCustomColor ? Color.primary : Color.clear, lineWidth: 2.5)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 12, height: 12)
                    }
                    .onTapGesture(count: 2) { openColorPanel() }
                    .onTapGesture(count: 1) { store.settings.useCustomColor = true; store.save() }
                    Text("自定义")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }.padding(.top, 14)
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10).fill(theme.swatch)
                .frame(width: 36, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(store.settings.theme == theme && !store.settings.useCustomColor ? Color.primary : Color.clear, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .onTapGesture { store.settings.theme = theme; store.settings.useCustomColor = false; store.save() }
            Text(theme.label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(store.settings.customColor ?? .gray)
        panel.orderFront(nil)
        // 监听颜色变化
        if let old = colorPanelObserver { NotificationCenter.default.removeObserver(old) }
        colorPanelObserver = NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification, object: panel, queue: .main
        ) { [self] _ in
            if let c = panel.color.usingColorSpace(.sRGB) {
                store.settings.customColorR = c.redComponent
                store.settings.customColorG = c.greenComponent
                store.settings.customColorB = c.blueComponent
                store.settings.useCustomColor = true
                store.save()
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundColor(.secondary)
    }
}

// MARK: - Embedded Calendar (直接嵌入设置页)

struct EmbeddedCalendar: View {
    @ObservedObject var store: DataStore
    @State private var displayMonth: Int
    @State private var displayYear: Int
    @State private var selectedDay: DayInfo?
    @State private var showDetail = false

    private let cal = Calendar.current

    init(store: DataStore) {
        self.store = store
        let now = Date()
        _displayMonth = State(initialValue: Calendar.current.component(.month, from: now))
        _displayYear = State(initialValue: Calendar.current.component(.year, from: now))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 4) {
                // 月份切换
                HStack {
                    Button { withAnimation(.easeOut(duration: 0.1)) { prevMonth() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22).background(Color(white: 0.94)).cornerRadius(5)
                    }.buttonStyle(.plain)
                    Spacer()
                    Text("\(String(displayYear))年\(displayMonth)月")
                        .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.1)) { nextMonth() } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium))
                            .frame(width: 22, height: 22).background(Color(white: 0.94)).cornerRadius(5)
                    }.buttonStyle(.plain)
                }

                // 星期
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 0) {
                    ForEach(["日","一","二","三","四","五","六"], id: \.self) { d in
                        Text(d).font(.system(size: 9, weight: .medium)).foregroundColor(Color(white: 0.55)).frame(height: 16)
                    }
                }

                // 日历
                let days = generateDays()
                let rowCount = (days.count + 6) / 7

                VStack(spacing: 4) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        ZStack {
                            Rectangle().fill(Color(white: 0.84)).frame(height: 0.5).offset(y: -30)
                            HStack(spacing: 4) {
                                ForEach(0..<7, id: \.self) { col in
                                    let idx = row * 7 + col
                                    if idx < days.count { dayCard(days[idx]) }
                                    else { Color.clear.frame(height: 68) }
                                }
                            }
                        }
                    }
                }
            }

            // 弹窗
            if showDetail, let day = selectedDay {
                ZStack {
                    Color.black.opacity(0.15).onTapGesture { withAnimation(.easeOut(duration: 0.1)) { showDetail = false } }
                    DayDetailView(store: store, day: day, onDismiss: { withAnimation(.easeOut(duration: 0.1)) { showDetail = false } })
                        .frame(width: 280)
                        .background(.regularMaterial).cornerRadius(12)
                        .shadow(color: .black.opacity(0.12), radius: 12)
                }.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: showDetail)
    }

    private func dayCard(_ day: DayInfo) -> some View {
        Group {
            if day.isPlaceholder {
                Color.clear.frame(height: 68)
            } else {
                let hasEvent = !day.events.isEmpty
                ZStack(alignment: .top) {
                    Rectangle().fill(Color(white: 0.78)).frame(width: 0.5, height: 5).offset(y: -2)
                    VStack(spacing: 1) {
                        Spacer().frame(height: 3)
                        Text("\(day.day)")
                            .font(.system(size: 14, weight: day.isToday ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundColor(day.isToday ? store.settings.activeAccentDeep : Color(white: 0.22))
                        VStack(spacing: 1) {
                            ForEach(day.events.prefix(2), id: \.self) { e in
                                Text(e).font(.system(size: 8, weight: .medium))
                                    .foregroundColor(store.settings.activeAccentDeep).lineLimit(1)
                            }
                        }.frame(maxHeight: .infinity)
                        Spacer().frame(height: 2)
                    }
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(SachetShape().fill(day.isToday ? store.settings.activeSwatch : hasEvent ? Color(white: 0.96) : Color(white: 0.99)))
                    .overlay(SachetShape().stroke(day.isToday ? store.settings.activeAccent.opacity(0.4) : hasEvent ? Color(white: 0.86) : Color(white: 0.91), lineWidth: 0.5))
                    .clipShape(SachetShape()).offset(y: 2)
                }
                .frame(height: 68)
                .rotationEffect(.degrees(day.rotation), anchor: .top)
                .onTapGesture { selectedDay = day; withAnimation(.easeOut(duration: 0.1)) { showDetail = true } }
            }
        }
    }

    private func generateDays() -> [DayInfo] {
        guard let first = cal.date(from: DateComponents(year: displayYear, month: displayMonth, day: 1)),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let wd = cal.component(.weekday, from: first)
        let today = cal.startOfDay(for: Date())
        let tD = cal.component(.day, from: today), tM = cal.component(.month, from: today), tY = cal.component(.year, from: today)
        var days: [DayInfo] = (0..<(wd-1)).map { _ in DayInfo(day: 0, month: displayMonth, year: displayYear, weekday: 0, events: [], isToday: false, rotation: 0) }
        for d in range {
            let date = cal.date(from: DateComponents(year: displayYear, month: displayMonth, day: d))!
            let w = cal.component(.weekday, from: date)
            let key = String(format: "%02d-%02d", displayMonth, d)
            var ev: [String] = []
            if let h = fixedHolidays[key] { ev.append(h) }
            if let t = solarTermDates.first(where: { $0.0 == displayMonth && $0.1 == d }) { ev.append(t.2) }
            for a in store.anniversaries where a.month == displayMonth && a.day == d { ev.append(a.name) }
            days.append(DayInfo(day: d, month: displayMonth, year: displayYear, weekday: w, events: ev,
                                isToday: d == tD && displayMonth == tM && displayYear == tY,
                                rotation: sin(Double(d * 7 + displayMonth * 13)) * 3.5))
        }
        return days
    }

    private func prevMonth() { if displayMonth == 1 { displayMonth = 12; displayYear -= 1 } else { displayMonth -= 1 } }
    private func nextMonth() { if displayMonth == 12 { displayMonth = 1; displayYear += 1 } else { displayMonth += 1 } }
}

private let fixedHolidays: [String: String] = [
    "01-01":"元旦","02-14":"情人节","03-08":"妇女节","03-12":"植树节",
    "04-01":"愚人节","05-01":"劳动节","05-04":"青年节","06-01":"儿童节",
    "07-01":"建党节","08-01":"建军节","09-10":"教师节","10-01":"国庆节",
    "10-31":"万圣节","12-24":"平安夜","12-25":"圣诞节",
]
private let solarTermDates: [(Int,Int,String)] = [
    (1,6,"小寒"),(1,20,"大寒"),(2,4,"立春"),(2,19,"雨水"),(3,6,"惊蛰"),(3,21,"春分"),
    (4,5,"清明"),(4,20,"谷雨"),(5,6,"立夏"),(5,21,"小满"),(6,6,"芒种"),(6,21,"夏至"),
    (7,7,"小暑"),(7,23,"大暑"),(8,7,"立秋"),(8,23,"处暑"),(9,8,"白露"),(9,23,"秋分"),
    (10,8,"寒露"),(10,23,"霜降"),(11,7,"立冬"),(11,22,"小雪"),(12,7,"大雪"),(12,22,"冬至"),
]
