import express, { type Request, type Response, type NextFunction } from 'express';
import { randomUUID } from 'crypto';
import { wechatConfigured } from './config.js';
import { store, type Candidate, type Reminder } from './store.js';
import { verifySignature, parseXml, createBindQr } from './wechat.js';
import { verifyAppleIdentityToken, issueSession, verifySession } from './auth.js';

// 把已鉴权请求的 ownerId 挂到 req 上
interface AuthedRequest extends Request { ownerId?: string; }

export function createServer() {
  const app = express();

  // 微信回调是 XML 文本；其余 API 走 JSON
  app.use('/wechat', express.text({ type: '*/*' }));
  app.use(express.json());

  // 健康检查
  app.get('/health', (_req, res) => res.json({ ok: true, wechatConfigured: wechatConfigured() }));

  // ===== 微信回调（无 owner 上下文，按 bindKey 绑定）=====
  app.get('/wechat', (req, res) => {
    const { signature, timestamp, nonce, echostr } = req.query as Record<string, string>;
    if (verifySignature(signature, timestamp, nonce)) res.send(echostr);
    else res.status(401).send('invalid signature');
  });

  app.post('/wechat', (req, res) => {
    const { signature, timestamp, nonce } = req.query as Record<string, string>;
    if (!verifySignature(signature, timestamp, nonce)) return res.status(401).send('invalid');
    const msg = parseXml(typeof req.body === 'string' ? req.body : '');
    if (msg.MsgType === 'event' && (msg.Event === 'subscribe' || msg.Event === 'SCAN')) {
      const key = (msg.EventKey || '').replace(/^qrscene_/, '');
      if (key) store.bind(key, msg.FromUserName);
    }
    res.send('success');
  });

  // ===== 登录：用 Apple identityToken 换后端会话 =====
  app.post('/api/auth/apple', async (req, res) => {
    try {
      const identityToken = req.body?.identityToken;
      if (!identityToken) return res.status(400).json({ error: '缺少 identityToken' });
      const ownerId = await verifyAppleIdentityToken(String(identityToken));
      const sessionToken = await issueSession(ownerId);
      res.json({ ownerId, sessionToken });
    } catch (e) {
      res.status(401).json({ error: 'Apple 验签失败: ' + (e as Error).message });
    }
  });

  // ===== Bearer 会话鉴权，解析 ownerId =====
  const auth = async (req: AuthedRequest, res: Response, next: NextFunction) => {
    const h = req.header('Authorization') ?? '';
    const token = h.startsWith('Bearer ') ? h.slice(7) : '';
    try {
      req.ownerId = await verifySession(token);
      next();
    } catch {
      res.status(401).json({ error: '未授权' });
    }
  };

  // 新建候选人 + 生成绑定二维码（归属当前 owner）
  app.post('/api/candidates/bind-qr', auth, async (req: AuthedRequest, res) => {
    try {
      const ownerId = req.ownerId!;
      const name = String(req.body?.name ?? '候选人');
      const bindKey = randomUUID().replace(/-/g, '').slice(0, 16);
      const c: Candidate = { id: randomUUID(), ownerId, name, bindKey };
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

  // 候选人列表（只看自己名下）
  app.get('/api/candidates', auth, (req: AuthedRequest, res) =>
    res.json(store.candidatesByOwner(req.ownerId!)));

  // 提交提醒（候选人必须属于当前 owner）
  app.post('/api/reminders', auth, (req: AuthedRequest, res) => {
    const ownerId = req.ownerId!;
    const { candidateId, text, remindAt } = req.body ?? {};
    if (!store.findCandidateForOwner(String(candidateId), ownerId)) {
      return res.status(404).json({ error: '候选人不存在或非本账号' });
    }
    const r: Reminder = {
      id: randomUUID(),
      ownerId,
      candidateId: String(candidateId),
      text: String(text ?? ''),
      remindAt: String(remindAt),
      status: 'pending',
    };
    store.addReminder(r);
    res.json(r);
  });

  // 查询提醒状态（只看自己名下）
  app.get('/api/reminders/:id', auth, (req: AuthedRequest, res) => {
    const r = store.reminderForOwner(req.params.id, req.ownerId!);
    if (!r) return res.status(404).json({ error: '不存在或非本账号' });
    res.json(r);
  });

  return app;
}
