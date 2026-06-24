import express, { type Request, type Response, type NextFunction } from 'express';
import { randomUUID } from 'crypto';
import { config, wechatConfigured } from './config.js';
import { store, type Candidate, type Reminder } from './store.js';
import { verifySignature, parseXml, createBindQr } from './wechat.js';

export function createServer() {
  const app = express();

  // 微信回调是 XML 文本；其余 API 走 JSON
  app.use('/wechat', express.text({ type: '*/*' }));
  app.use(express.json());

  // 健康检查
  app.get('/health', (_req, res) => res.json({ ok: true, wechatConfigured: wechatConfigured() }));

  // 微信服务器地址校验（公众平台保存配置时 GET）
  app.get('/wechat', (req, res) => {
    const { signature, timestamp, nonce, echostr } = req.query as Record<string, string>;
    if (verifySignature(signature, timestamp, nonce)) res.send(echostr);
    else res.status(401).send('invalid signature');
  });

  // 微信事件回调（关注 subscribe / 已关注扫码 SCAN → 绑定 openid）
  app.post('/wechat', (req, res) => {
    const { signature, timestamp, nonce } = req.query as Record<string, string>;
    if (!verifySignature(signature, timestamp, nonce)) return res.status(401).send('invalid');
    const msg = parseXml(typeof req.body === 'string' ? req.body : '');
    if (msg.MsgType === 'event' && (msg.Event === 'subscribe' || msg.Event === 'SCAN')) {
      const key = (msg.EventKey || '').replace(/^qrscene_/, '');
      if (key) store.bind(key, msg.FromUserName);
    }
    res.send('success'); // 微信要求回 success/空，否则会重试并提示“服务故障”
  });

  // ===== 给 app 的 API（简单 X-Api-Key 鉴权）=====
  const auth = (req: Request, res: Response, next: NextFunction) => {
    if (req.header('X-Api-Key') !== config.apiKey) return res.status(401).json({ error: '未授权' });
    next();
  };

  // 新建候选人 + 生成绑定二维码
  app.post('/api/candidates/bind-qr', auth, async (req, res) => {
    try {
      const name = String(req.body?.name ?? '候选人');
      const bindKey = randomUUID().replace(/-/g, '').slice(0, 16);
      const c: Candidate = { id: randomUUID(), name, bindKey };
      store.addCandidate(c);
      if (!wechatConfigured()) {
        return res.json({ candidate: c, qrUrl: null, note: '微信资质未配置，返回占位（联调用）' });
      }
      const { qrUrl } = await createBindQr(bindKey);
      res.json({ candidate: c, qrUrl });
    } catch (e) {
      res.status(500).json({ error: (e as Error).message });
    }
  });

  // 候选人列表（含绑定状态）
  app.get('/api/candidates', auth, (_req, res) => res.json(store.candidates()));

  // 提交提醒任务
  app.post('/api/reminders', auth, (req, res) => {
    const { candidateId, text, remindAt } = req.body ?? {};
    if (!store.findCandidate(candidateId)) return res.status(404).json({ error: '候选人不存在' });
    const r: Reminder = {
      id: randomUUID(),
      candidateId,
      text: String(text ?? ''),
      remindAt: String(remindAt),
      status: 'pending',
    };
    store.addReminder(r);
    res.json(r);
  });

  // 查询提醒状态
  app.get('/api/reminders/:id', auth, (req, res) => {
    const r = store.reminders().find(x => x.id === req.params.id);
    if (!r) return res.status(404).json({ error: '不存在' });
    res.json(r);
  });

  return app;
}
