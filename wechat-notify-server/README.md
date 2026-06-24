# wechat-notify-server

侧边待办的**微信模板消息提醒后端**——独立系统，独立部署、独立打包。
负责：接收微信服务号回调（关注/扫码→绑定 openid）、存储提醒任务、定时到点调微信模板消息下发；并对 app 暴露 REST API。

> 完整的「微信认证服务号申请 + 域名备案 + 模板配置 + 部署上线」操作手册见
> `../dev-doc/微信通知/微信适配与部署指南.md`。

## 快速开始（本地）

```bash
cp .env.example .env      # 填入微信资质(没有也能启动,占位联调)
npm install
npm run build
npm start                 # 监听 :9528
# 或开发热重载： npm run dev
```

健康检查：`curl http://127.0.0.1:9528/health`

## 环境变量

见 `.env.example`。关键项：`WECHAT_APPID / WECHAT_APPSECRET / WECHAT_TOKEN / WECHAT_TEMPLATE_ID`、`API_KEY`（app↔后端鉴权）、`PORT`（默认 9528，内网，由 nginx 反代到 https）。

## API（供 macOS app 调用，需 `X-Api-Key`）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/health` | 健康检查（无需鉴权） |
| POST | `/api/candidates/bind-qr` | body `{name}` → 新建候选人 + 返回绑定二维码 `qrUrl` |
| GET | `/api/candidates` | 候选人列表（含 `openid`/`boundAt` 绑定状态） |
| POST | `/api/reminders` | body `{candidateId,text,remindAt(ISO)}` → 创建提醒 |
| GET | `/api/reminders/:id` | 查询提醒状态（pending/sent/failed/read） |

## 微信回调（公众平台「服务器配置」填这两个，同一 URL）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/wechat` | 服务器地址校验（echostr） |
| POST | `/wechat` | 接收关注/扫码事件，据带参二维码 scene 绑定 openid |

## 数据

轻量 JSON 持久化（`DATA_FILE`，默认 `./data/store.json`）。低频场景足够；如需更强可后续换 SQLite。
