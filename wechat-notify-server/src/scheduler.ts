import { store } from './store.js';
import { sendTemplate } from './wechat.js';
import { config, wechatConfigured } from './config.js';

/** 每 30 秒扫描到点且未发送的提醒，调微信模板消息下发 */
export function startScheduler(): void {
  setInterval(() => {
    void tick();
  }, 30_000);
}

async function tick(): Promise<void> {
  if (!wechatConfigured()) return;
  const due = store.duePending(new Date());
  for (const r of due) {
    const c = store.findCandidate(r.candidateId);
    if (!c?.openid) {
      store.updateReminder(r.id, { status: 'failed', error: '候选人未绑定微信' });
      continue;
    }
    try {
      await sendTemplate(
        c.openid,
        {
          thing: { value: r.text || '待办提醒' },
          time: { value: new Date(r.remindAt).toLocaleString('zh-CN') },
          remark: { value: '来自侧边待办' },
        },
        config.detailBaseUrl || undefined,
      );
      store.updateReminder(r.id, { status: 'sent', sentAt: new Date().toISOString() });
    } catch (e) {
      store.updateReminder(r.id, { status: 'failed', error: (e as Error).message });
    }
  }
}
