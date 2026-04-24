# Git 提交规范

## Conventional Commits

```
<type>(<scope>): <description>

<optional body>
```

### 类型

| 类型 | 说明 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `refactor` | 重构（不改功能） |
| `docs` | 文档 |
| `test` | 测试 |
| `chore` | 构建/工具 |
| `perf` | 性能优化 |
| `ci` | CI/CD |

### 规范

- 描述用中文，简洁明了
- scope 可选，标注影响模块
- body 解释 why，不是 what
- 提交前确认没带上 `.env` / `.secrets/`
