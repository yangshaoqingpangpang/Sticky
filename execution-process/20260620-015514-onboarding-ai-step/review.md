# 执行过程评审 — 引导加 AI 步骤 + 改名措辞 + 升 build

## 改动
1. ContentView onboardingSteps: 新增「AI 帮手」引导步骤(介绍 ✦ 自动检索),第 4 步"便笺工具"措辞改"侧边待办"并补"配置 AI 大模型"
2. project.yml: build 号 10→11(同版本 1.0.6 迭代,App Store build 必须递增)

## 影响范围核查清单
- [x] onboardingSteps 纯数组新增/改文案:不改引导触发/推进逻辑,steps.count 自动适配
- [x] 新增步骤复用 "todo" 锚点:锚点已存在,无需新增 onboardingAnchor
- [x] build 号递增:仅打包元数据,不影响功能;bundle ID 不变,数据安全
- [x] 无逻辑改动,无数据风险

## 测试证据
- swift build 通过
- archive 成功,包内无用户数据/密钥

## 评审结论
✅ 通过 — 纯文案/引导数据 + 版本号,零逻辑风险。
