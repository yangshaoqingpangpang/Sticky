import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: DataStore
    @Binding var page: PanelPage
    @State private var colorPanelObserver: Any?
    @State private var backupAlert: String?

    // AI 配置本地编辑态(onAppear 从 settings 载入,保存时写回)
    @State private var aiProvider: AIProvider = .deepseek
    @State private var aiModel = ""
    @State private var aiURL = ""
    @State private var aiKey = ""
    @State private var aiPrompt = ""
    @State private var aiPromptExpanded = false
    @State private var aiEditExpanded = false
    @State private var aiLoaded = false
    @State private var aiTesting = false
    @State private var aiStatus: (ok: Bool, text: String)?

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Rectangle().fill(Color.nuOutlineVariant.opacity(0.4)).frame(height: 0.5).padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsCard { themeSection }
                    settingsCard { backupSection }
                    settingsCard {
                        sectionLabel("纪念日")
                        EmbeddedCalendar(store: store)
                    }
                    settingsCard { aiSection }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color.nuSurface)
        .onAppear(perform: loadAIConfig)
        .alert("数据备份", isPresented: Binding(get: { backupAlert != nil }, set: { if !$0 { backupAlert = nil } })) {
            Button("好的", role: .cancel) { backupAlert = nil }
        } message: {
            Text(backupAlert ?? "")
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("数据备份")
            Text("导出会把全部待办、片段、纪念日、笔记及图片打包成一个文件；导入会用所选备份覆盖当前数据。")
                .font(.system(size: 10.5)).foregroundColor(.nuOutline)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    let r = store.exportBackup()
                    if r.message != "已取消" { backupAlert = r.message }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11, weight: .medium))
                        Text("导出备份").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(store.settings.activeAccentDeep)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(store.settings.activeAccent.opacity(0.12))
                    .cornerRadius(8)
                }.buttonStyle(.plain)

                Button {
                    let r = store.importBackup()
                    if r.message != "已取消" { backupAlert = r.message }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 11, weight: .medium))
                        Text("导入备份").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.nuOnSurfaceVariant)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.nuGray6)
                    .cornerRadius(8)
                }.buttonStyle(.plain)
            }
        }
    }

    // 分组卡片容器:白底圆角 + 细边框
    @ViewBuilder private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(white: 0.93), lineWidth: 0.5))
    }

    // MARK: - AI 配置

    private func loadAIConfig() {
        guard !aiLoaded else { return }
        aiLoaded = true
        let s = store.settings
        aiProvider = s.aiProvider
        aiModel = s.aiModelName ?? s.aiProvider.defaultModel
        aiURL = s.aiBaseURL ?? s.aiProvider.defaultBaseURL
        aiKey = s.aiAPIKey ?? ""
        aiPrompt = s.aiSearchPrompt ?? DataStore.defaultSearchPrompt
    }

    /// 切换供应商:用该供应商默认值覆盖 URL/模型名(自定义除外,保留用户已填内容)
    private func onProviderChange(_ p: AIProvider) {
        aiProvider = p
        aiStatus = nil
        if p != .custom {
            aiURL = p.defaultBaseURL
            aiModel = p.defaultModel
        }
    }

    private func saveAIConfig() {
        store.settings.aiProvider = aiProvider
        store.settings.aiBaseURL = aiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.aiModelName = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.aiAPIKey = aiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        store.settings.aiSearchPrompt = (p.isEmpty || p == DataStore.defaultSearchPrompt) ? nil : p
        store.save()
        aiStatus = (true, "已保存")
    }

    private var aiConfigured: Bool {
        !aiURL.trimmingCharacters(in: .whitespaces).isEmpty && !aiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var aiCustomPrompt: Bool {
        let p = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return !p.isEmpty && p != DataStore.defaultSearchPrompt
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("AI 配置")
                Spacer()
                if aiEditExpanded {
                    Button("收起") { withAnimation(.easeOut(duration: 0.18)) { aiEditExpanded = false } }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .buttonStyle(.plain)
                }
            }
            if aiEditExpanded { aiEditor } else { aiSummaryRows }
        }
    }

    // 收起态:紧凑摘要行(对齐设计稿),点击展开完整编辑器
    private var aiSummaryRows: some View {
        VStack(spacing: 0) {
            aiRow(title: "大模型", value: aiProvider.label)
            aiRowDivider
            aiRow(title: "接口地址", value: aiConfigured ? "已配置" : "未配置", check: aiConfigured)
            aiRowDivider
            aiRow(title: "检索提示词", value: aiCustomPrompt ? "自定义" : "默认")
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { aiEditExpanded = true } }
    }

    private func aiRow(title: String, value: String, check: Bool = false) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundColor(.nuOnSurface)
            Spacer()
            Text(value).font(.system(size: 12)).foregroundColor(.nuOutline)
            Image(systemName: check ? "checkmark" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(check ? Color.nuGreen : Color.nuOutlineVariant)
        }
        .padding(.vertical, 9)
    }

    private var aiRowDivider: some View { Rectangle().fill(Color.nuGray6).frame(height: 1) }

    // 展开态:完整编辑器(供应商/模型名/接口/Key/提示词/保存/测试)
    private var aiEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置大模型供应商、接口地址与 API Key，保存后作为调用大模型的凭证。")
                .font(.system(size: 10.5)).foregroundColor(.nuOutline)
                .fixedSize(horizontal: false, vertical: true)

            // 供应商下拉
            HStack(spacing: 8) {
                Text("大模型").font(.system(size: 12, weight: .medium)).foregroundColor(.nuOnSurfaceVariant).frame(width: 56, alignment: .leading)
                Picker("", selection: Binding(get: { aiProvider }, set: { onProviderChange($0) })) {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        Text(p.label).tag(p)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            aiField(label: "模型名", text: $aiModel, placeholder: "如 deepseek-chat")
            aiField(label: "接口地址", text: $aiURL, placeholder: "https://…")
            aiSecureField(label: "API Key", text: $aiKey, placeholder: "sk-…")

            // 检索提示词(可折叠,默认收起)
            HStack(spacing: 4) {
                Text("检索提示词").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                Image(systemName: aiPromptExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                if aiPromptExpanded {
                    Button("恢复默认") { aiPrompt = DataStore.defaultSearchPrompt }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(store.settings.activeAccentDeep)
                        .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { aiPromptExpanded.toggle() } }

            Text("您可以自行总结工作习惯，自定义 prompt 来提效").font(.system(size: 9.5)).foregroundColor(.nuOutline)

            if aiPromptExpanded {
                Text("用 {{todo}} 代表待办内容").font(.system(size: 9.5)).foregroundColor(.nuOutline)
                TextEditor(text: $aiPrompt)
                    .font(.system(size: 11))
                    .frame(height: 120)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.nuGray6))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.nuOutlineVariant.opacity(0.5), lineWidth: 0.5))
                    .scrollContentBackground(.hidden)
            }

            HStack(spacing: 10) {
                Button { saveAIConfig() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle").font(.system(size: 11, weight: .medium))
                        Text("保存").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(store.settings.activeAccentDeep)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(store.settings.activeAccent.opacity(0.12))
                    .cornerRadius(8)
                }.buttonStyle(.plain)

                Button {
                    aiTesting = true; aiStatus = nil
                    let p = aiProvider, u = aiURL, k = aiKey, m = aiModel
                    Task {
                        let r = await store.testAIConnection(provider: p, baseURL: u, apiKey: k, model: m)
                        await MainActor.run { aiStatus = (r.ok, r.message); aiTesting = false }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if aiTesting {
                            ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 11, height: 11)
                        } else {
                            Image(systemName: "bolt.horizontal.circle").font(.system(size: 11, weight: .medium))
                        }
                        Text(aiTesting ? "测试中…" : "测试连接").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.nuOnSurfaceVariant)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.nuGray6)
                    .cornerRadius(8)
                }.buttonStyle(.plain).disabled(aiTesting)

                // 大 UI:状态提示在按钮右侧,单行不换行
                if store.settings.sizeMode == .large, let s = aiStatus {
                    aiStatusView(s, wrap: false)
                }
                Spacer(minLength: 0)
            }

            // 小 UI:状态提示换行显示在按钮下方
            if store.settings.sizeMode == .small, let s = aiStatus {
                aiStatusView(s, wrap: true)
            }
        }
    }

    private func aiStatusView(_ s: (ok: Bool, text: String), wrap: Bool) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: s.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(s.text).font(.system(size: 10.5))
                .lineLimit(wrap ? nil : 1)
                .fixedSize(horizontal: false, vertical: wrap)
        }
        .foregroundColor(s.ok ? Color.nuGreen : Color.orange)
    }

    private func aiField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.nuOnSurfaceVariant).frame(width: 56, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }

    private func aiSecureField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.nuOnSurfaceVariant).frame(width: 56, alignment: .leading)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder).font(.system(size: 12))
        }
    }

    private var settingsHeader: some View {
        ZStack {
            Text("设置").font(.system(size: 16, weight: .semibold)).foregroundColor(.nuOnSurface)
                .frame(maxWidth: .infinity)
            HStack {
                Button { withAnimation { page = .main } } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                        Text("返回")
                    }.font(.system(size: 13)).foregroundColor(store.settings.activeAccentDeep)
                }.buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
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
                    .gesture(
                        ExclusiveGesture(
                            TapGesture(count: 2).onEnded { openColorPanel() },
                            TapGesture(count: 1).onEnded { store.settings.useCustomColor = true; store.save() }
                        )
                    )
                    Text("自定义")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }.frame(maxWidth: .infinity)
        }
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
        // LSUIElement(配件)应用需先激活,否则系统颜色面板不会显示
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.color = NSColor(store.settings.customColor ?? .gray)
        panel.makeKeyAndOrderFront(nil)
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

    // 一级:section 标题(主题色,作为卡片分组标题)
    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundColor(store.settings.activeAccentDeep)
    }
}

// MARK: - Embedded Calendar (直接嵌入设置页)

struct EmbeddedCalendar: View {
    @ObservedObject var store: DataStore
    @State private var displayMonth: Int
    @State private var displayYear: Int
    @State private var selectedDay: DayInfo?
    @State private var showDetail = false
    @FocusState private var ymField: YMField?
    @State private var yearText = ""
    @State private var monthText = ""
    private enum YMField { case year, month }

    private let cal = Calendar.current

    init(store: DataStore) {
        self.store = store
        let now = Date()
        _displayMonth = State(initialValue: Calendar.current.component(.month, from: now))
        _displayYear = State(initialValue: Calendar.current.component(.year, from: now))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                // 月份切换
                HStack {
                    Button { withAnimation(.easeOut(duration: 0.1)) { prevMonth() } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                            .foregroundColor(.nuOnSurfaceVariant).frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                    Spacer()
                    // 可编辑年月:淡灰外框提示可手动改,方便提前很久设置纪念日
                    HStack(spacing: 3) {
                        TextField("", text: $yearText)
                            .textFieldStyle(.plain).frame(width: 40).multilineTextAlignment(.center)
                            .focused($ymField, equals: .year)
                            .onSubmit { ymField = nil }
                        Text("年")
                        TextField("", text: $monthText)
                            .textFieldStyle(.plain).frame(width: 20).multilineTextAlignment(.center)
                            .focused($ymField, equals: .month)
                            .onSubmit { ymField = nil }
                        Text("月")
                    }
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundColor(.nuOnSurface)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(white: 0.82), lineWidth: 1))
                    .onChange(of: ymField) { _, f in if f == nil { syncYMText() } }
                    .onChange(of: yearText) { _, _ in applyYM() }
                    .onChange(of: monthText) { _, _ in applyYM() }
                    .onAppear { syncYMText() }
                    .onChange(of: displayYear) { _, _ in if ymField == nil { syncYMText() } }
                    .onChange(of: displayMonth) { _, _ in if ymField == nil { syncYMText() } }
                    Spacer()
                    Button { withAnimation(.easeOut(duration: 0.1)) { nextMonth() } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium))
                            .foregroundColor(.nuOnSurfaceVariant).frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                }

                // 星期
                HStack(spacing: 6) {
                    ForEach(["日","一","二","三","四","五","六"], id: \.self) { d in
                        Text(d).font(.system(size: 11, weight: .medium)).foregroundColor(.nuOutline)
                            .frame(maxWidth: .infinity)
                    }
                }

                // 日历
                let days = generateDays()
                let rowCount = (days.count + 6) / 7

                VStack(spacing: 6) {
                    ForEach(0..<rowCount, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { col in
                                let idx = row * 7 + col
                                if idx < days.count { dayCard(days[idx]) }
                                else { Color.clear.frame(maxWidth: .infinity).frame(height: 48) }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.nuOutlineVariant.opacity(0.5), lineWidth: 1))

            // 弹窗
            if showDetail, let day = selectedDay {
                ZStack {
                    Color.black.opacity(0.15).onTapGesture { withAnimation(.easeOut(duration: 0.1)) { showDetail = false } }
                    DayDetailView(store: store, day: day, onDismiss: { withAnimation(.easeOut(duration: 0.1)) { showDetail = false } })
                        .frame(width: 280)
                        .background(Color.white).cornerRadius(12)
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                }.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.1), value: showDetail)
    }

    private func dayCard(_ day: DayInfo) -> some View {
        Group {
            if day.isPlaceholder {
                Color.clear.frame(maxWidth: .infinity).frame(height: 48)
            } else {
                let hasEvent = !day.events.isEmpty
                VStack(spacing: 1) {
                    Text("\(day.day)")
                        .font(.system(size: 14, weight: day.isToday ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundColor(day.isToday ? store.settings.activeAccentDeep : .nuOnSurface)
                    if let e = day.events.first {
                        Text(e).font(.system(size: 8, weight: .medium))
                            .foregroundColor(store.settings.activeAccentDeep).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(day.isToday ? store.settings.activeSwatch
                              : (hasEvent ? Color.nuGray6.opacity(0.7) : Color.nuGray6.opacity(0.35)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(day.isToday ? store.settings.activeAccent : Color.clear,
                                lineWidth: day.isToday ? 2 : 0)
                )
                .contentShape(Rectangle())
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

    private func syncYMText() { yearText = String(displayYear); monthText = String(displayMonth) }
    // 边输入边跳转:仅当输入构成合法范围内的数字时才应用(如"2027"打到第4位才跳,不会在"2"时乱跳)
    private func applyYM() {
        if let y = Int(yearText.filter(\.isNumber)), (1970...2200).contains(y) { displayYear = y }
        if let m = Int(monthText.filter(\.isNumber)), (1...12).contains(m) { displayMonth = m }
    }
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
