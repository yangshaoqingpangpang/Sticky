# 执行过程评审 — 修复状态栏"退出"灰掉(苹果审核 2.1a bug)

## 根因
createStatusItem 里 `for item in menu.items { item.target = self }` 把"退出"项 target 设成 AppDelegate;
但"退出" action 是 NSApplication.terminate(_:),AppDelegate 不响应该 selector → AppKit 菜单验证判定不可响应 → 菜单项禁用变灰。审核员看到 "the quit button is grey out"。

## 修复
- 拆开设置:toggle 项 target=self(AppDelegate 响应 toggle ✓);
- 退出项 target=NSApp(NSApplication 响应 terminate: ✓)→ 菜单项启用可点。

## 影响范围核查清单
- [x] 仅改 createStatusItem 菜单 target 赋值,不动菜单结构/action/快捷键
- [x] toggle 行为不变(仍 target=self)
- [x] 退出行为正确(target=NSApp,terminate:)
- [x] build 11→12(App Store 重新提交)
- [x] 无数据风险,bundle ID 不变

## 测试证据
- swift build + archive 双通过
- 修复符合 AppKit 标准菜单验证机制(target 必须响应 action 才启用)

## 评审结论
✅ 通过 — 精准修复审核反馈的灰掉 bug,无副作用。
