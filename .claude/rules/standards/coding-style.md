# 编码规范

> 同 basic 版本，详见 template/basic/.claude/rules/coding-style.md

## 通用规则

1. 枚举值必须映射为中文
2. 枚举字段用下拉框，禁止手动输入
3. 格式化字段必须正则校验
4. 禁止让用户输入关联表 ID
5. 时间格式统一 `YYYY-MM-DD HH:mm:ss`
6. 数组调 `.map()` 前用 `?? []` 兜底
7. 类型检查 + 生产构建双通过
8. 禁止硬编码 localhost
9. 禁止使用假数据
10. 遵循现有代码风格
