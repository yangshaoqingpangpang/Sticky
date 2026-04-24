import SwiftUI

// MARK: - Holidays & solar terms

private let fixedHolidays: [String: String] = [
    "01-01": "元旦", "02-14": "情人节", "03-08": "妇女节", "03-12": "植树节",
    "04-01": "愚人节", "05-01": "劳动节", "05-04": "青年节", "06-01": "儿童节",
    "07-01": "建党节", "08-01": "建军节", "09-10": "教师节", "10-01": "国庆节",
    "10-31": "万圣节", "12-24": "平安夜", "12-25": "圣诞节",
]

private let solarTermDates: [(Int, Int, String)] = [
    (1,6,"小寒"),(1,20,"大寒"),(2,4,"立春"),(2,19,"雨水"),
    (3,6,"惊蛰"),(3,21,"春分"),(4,5,"清明"),(4,20,"谷雨"),
    (5,6,"立夏"),(5,21,"小满"),(6,6,"芒种"),(6,21,"夏至"),
    (7,7,"小暑"),(7,23,"大暑"),(8,7,"立秋"),(8,23,"处暑"),
    (9,8,"白露"),(9,23,"秋分"),(10,8,"寒露"),(10,23,"霜降"),
    (11,7,"立冬"),(11,22,"小雪"),(12,7,"大雪"),(12,22,"冬至"),
]

private let weekdayNames = ["", "日", "一", "二", "三", "四", "五", "六"]

// MARK: - Day info

struct DayInfo: Identifiable {
    let id = UUID()
    let day: Int
    let month: Int
    let year: Int
    let weekday: Int
    let events: [String]
    let isToday: Bool
    let rotation: Double
    var isPlaceholder: Bool { day == 0 }
}

// MARK: - Main view

struct AnniversaryView: View {
    @ObservedObject var store: DataStore
    @Binding var page: PanelPage
    var onBack: (() -> Void)? = nil  // 从设置页进来时用

    @State private var displayMonth: Int
    @State private var displayYear: Int
    @State private var selectedDay: DayInfo?
    @State private var showDetail = false

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(store: DataStore, page: Binding<PanelPage>, onBack: (() -> Void)? = nil) {
        self.store = store
        self._page = page
        self.onBack = onBack
        let now = Date()
        _displayMonth = State(initialValue: Calendar.current.component(.month, from: now))
        _displayYear = State(initialValue: Calendar.current.component(.year, from: now))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { if let back = onBack { back() } else { withAnimation { page = .main } } } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left").font(.system(size: 12))
                            Text("返回")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(store.settings.activeAccent)
                    }
                    .buttonStyle(.plain)
                    Text("纪念日").font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)

                Divider().padding(.horizontal, 14)

                // Month selector
                HStack {
                    Button { withAnimation(.easeOut(duration: 0.15)) { prevMonth() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.94)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(String(displayYear))年\(displayMonth)月")
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.15)) { nextMonth() } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .background(Color(white: 0.94)).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(Color(white: 0.3))
                .padding(.horizontal, 20).padding(.vertical, 10)

                // Weekday labels
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(["日","一","二","三","四","五","六"], id: \.self) { d in
                        Text(d).font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(white: 0.55)).frame(height: 18)
                    }
                }
                .padding(.horizontal, 10)

                // Calendar grid — tall cards
                ScrollView {
                    calendarGrid.padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 16)
                }
            }
            .background(.background)

            // Inline detail popup
            if showDetail, let day = selectedDay {
                ZStack {
                    Color.black.opacity(0.2).onTapGesture { withAnimation(.easeOut(duration: 0.12)) { showDetail = false } }
                    DayDetailView(store: store, day: day, onDismiss: { withAnimation(.easeOut(duration: 0.12)) { showDetail = false } })
                        .frame(width: 300)
                        .background(.regularMaterial)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.15), radius: 16)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showDetail)
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let days = generateDays()
        let rowCount = (days.count + 6) / 7

        return VStack(spacing: 6) {
            ForEach(0..<rowCount, id: \.self) { row in
                ZStack {
                    // Clothesline (thin string)
                    Rectangle().fill(Color(white: 0.82)).frame(height: 0.5).offset(y: -34)

                    HStack(spacing: 5) {
                        ForEach(0..<7, id: \.self) { col in
                            let idx = row * 7 + col
                            if idx < days.count {
                                dayCard(days[idx])
                            } else {
                                Color.clear.frame(height: 80)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Day card (香囊 sachet shape)

    private func dayCard(_ day: DayInfo) -> some View {
        Group {
            if day.isPlaceholder {
                Color.clear.frame(height: 80)
            } else {
                let hasEvent = !day.events.isEmpty
                ZStack(alignment: .top) {
                    // Short string from clothesline to sachet top
                    Rectangle()
                        .fill(Color(white: 0.78))
                        .frame(width: 0.5, height: 6)
                        .offset(y: -3)

                    // Sachet body
                    VStack(spacing: 2) {
                        Spacer().frame(height: 4)

                        // Date
                        Text("\(day.day)")
                            .font(.system(size: 16, weight: day.isToday ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundColor(day.isToday ? store.settings.activeAccentDeep : Color(white: 0.22))

                        // Events
                        VStack(spacing: 1) {
                            ForEach(day.events.prefix(2), id: \.self) { e in
                                Text(e)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(store.settings.activeAccentDeep)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxHeight: .infinity)

                        if day.events.count > 2 {
                            Text("+\(day.events.count - 2)")
                                .font(.system(size: 6, weight: .medium))
                                .foregroundColor(Color(white: 0.5))
                        }

                        Spacer().frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(
                        SachetShape()
                            .fill(day.isToday ? store.settings.activeSwatch :
                                    hasEvent ? Color(white: 0.97) : Color(white: 0.99))
                            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                    )
                    .overlay(
                        SachetShape()
                            .stroke(day.isToday ? store.settings.activeAccent.opacity(0.35) :
                                        hasEvent ? Color(white: 0.86) : Color(white: 0.91), lineWidth: 0.5)
                    )
                    .clipShape(SachetShape())
                    .offset(y: 3)
                }
                .frame(height: 80)
                .rotationEffect(.degrees(day.rotation), anchor: .top)
                .onTapGesture {
                    selectedDay = day
                    withAnimation(.easeOut(duration: 0.12)) { showDetail = true }
                }
            }
        }
    }

    // MARK: - Data

    private func generateDays() -> [DayInfo] {
        guard let firstOfMonth = cal.date(from: DateComponents(year: displayYear, month: displayMonth, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth) else { return [] }

        let weekday = cal.component(.weekday, from: firstOfMonth)
        let today = cal.startOfDay(for: Date())
        let todayD = cal.component(.day, from: today)
        let todayM = cal.component(.month, from: today)
        let todayY = cal.component(.year, from: today)

        var days: [DayInfo] = []

        for _ in 0..<(weekday - 1) {
            days.append(DayInfo(day: 0, month: displayMonth, year: displayYear, weekday: 0, events: [], isToday: false, rotation: 0))
        }

        for d in range {
            let date = cal.date(from: DateComponents(year: displayYear, month: displayMonth, day: d))!
            let wd = cal.component(.weekday, from: date)
            let key = String(format: "%02d-%02d", displayMonth, d)
            var events: [String] = []
            if let h = fixedHolidays[key] { events.append(h) }
            if let t = solarTermDates.first(where: { $0.0 == displayMonth && $0.1 == d }) { events.append(t.2) }
            for a in store.anniversaries where a.month == displayMonth && a.day == d { events.append(a.name) }

            let isToday = d == todayD && displayMonth == todayM && displayYear == todayY
            let rot = sin(Double(d * 7 + displayMonth * 13)) * 3.5

            days.append(DayInfo(day: d, month: displayMonth, year: displayYear, weekday: wd, events: events, isToday: isToday, rotation: rot))
        }
        return days
    }

    private func prevMonth() { if displayMonth == 1 { displayMonth = 12; displayYear -= 1 } else { displayMonth -= 1 } }
    private func nextMonth() { if displayMonth == 12 { displayMonth = 1; displayYear += 1 } else { displayMonth += 1 } }
}

// MARK: - 香囊形状：顶部收窄，身体宽，底部圆角

struct SachetShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let neckW = w * 0.5       // 顶部收窄到 50%
        let neckH: CGFloat = 8    // 收窄过渡高度
        let r: CGFloat = 6        // 底部圆角

        var p = Path()
        let neckL = (w - neckW) / 2
        let neckR = neckL + neckW

        // 顶部中心左
        p.move(to: CGPoint(x: neckL, y: 0))

        // 左侧斜线展开
        p.addQuadCurve(to: CGPoint(x: 0, y: neckH),
                       control: CGPoint(x: neckL * 0.3, y: neckH * 0.5))

        // 左边
        p.addLine(to: CGPoint(x: 0, y: h - r))

        // 左下圆角
        p.addArc(center: CGPoint(x: r, y: h - r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)

        // 底边
        p.addLine(to: CGPoint(x: w - r, y: h))

        // 右下圆角
        p.addArc(center: CGPoint(x: w - r, y: h - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)

        // 右边
        p.addLine(to: CGPoint(x: w, y: neckH))

        // 右侧斜线收窄
        p.addQuadCurve(to: CGPoint(x: neckR, y: 0),
                       control: CGPoint(x: w - neckL * 0.3, y: neckH * 0.5))

        p.closeSubpath()
        return p
    }
}

// MARK: - Day detail popup

struct DayDetailView: View {
    @ObservedObject var store: DataStore
    let day: DayInfo
    var onDismiss: () -> Void
    @State private var newName = ""

    private var dayAnniversaries: [Anniversary] {
        store.anniversaries.filter { $0.month == day.month && $0.day == day.day }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(day.month)月\(day.day)日  \(weekdayNames[day.weekday])")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundColor(Color(white: 0.7))
                }.buttonStyle(.plain)
            }

            Divider()

            if day.events.isEmpty && dayAnniversaries.isEmpty {
                Text("这天没有事件").font(.system(size: 13)).foregroundColor(Color(white: 0.6))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(day.events.filter { e in !dayAnniversaries.contains(where: { $0.name == e }) }, id: \.self) { event in
                        HStack(spacing: 8) {
                            Circle().fill(Color(white: 0.75)).frame(width: 5, height: 5)
                            Text(event).font(.system(size: 13)).foregroundColor(Color(white: 0.4))
                            Spacer()
                            Text("节日").font(.system(size: 10)).foregroundColor(Color(white: 0.7))
                        }.padding(.vertical, 2)
                    }
                    ForEach(dayAnniversaries) { a in
                        HStack(spacing: 8) {
                            Circle().fill(store.settings.activeAccent).frame(width: 5, height: 5)
                            Text(a.name).font(.system(size: 13))
                            Spacer()
                            Button {
                                let remaining = store.anniversaries.filter { $0.month == day.month && $0.day == day.day && $0.id != a.id }
                                store.deleteAnniversary(a.id)
                                if remaining.isEmpty { onDismiss() }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 11)).foregroundColor(Color(white: 0.6))
                            }.buttonStyle(.plain)
                        }.padding(.vertical, 2)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("添加纪念日（最多7字）", text: $newName)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .onChange(of: newName) { _, v in if v.count > 7 { newName = String(v.prefix(7)) } }
                Button {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    store.addAnniversary(month: day.month, day: day.day, name: n)
                    newName = ""
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(store.settings.activeAccent)
                }
                .buttonStyle(.plain)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }
}
