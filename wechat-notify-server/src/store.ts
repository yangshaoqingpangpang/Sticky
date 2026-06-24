import fs from 'fs';
import path from 'path';
import { config } from './config.js';

export interface Candidate {
  id: string;
  name: string;          // 备注名（app 内可改）
  bindKey: string;       // 带参二维码 scene_str，扫码后据此绑定 openid
  openid?: string;
  nickname?: string;
  boundAt?: string;
}

export interface Reminder {
  id: string;
  candidateId: string;
  text: string;
  remindAt: string;      // ISO 时间
  status: 'pending' | 'sent' | 'failed' | 'read';
  sentAt?: string;
  error?: string;
}

interface DB { candidates: Candidate[]; reminders: Reminder[]; }

let db: DB = { candidates: [], reminders: [] };
const file = path.resolve(config.dataFile);

export function load(): void {
  try {
    db = JSON.parse(fs.readFileSync(file, 'utf-8'));
  } catch {
    db = { candidates: [], reminders: [] };
    persist();
  }
}

function persist(): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(db, null, 2));
}

export const store = {
  candidates: (): Candidate[] => db.candidates,
  reminders: (): Reminder[] => db.reminders,
  findCandidate: (id: string): Candidate | undefined => db.candidates.find(c => c.id === id),
  addCandidate(c: Candidate): void { db.candidates.push(c); persist(); },

  /** 扫码关注事件回调时据 bindKey 绑定 openid */
  bind(bindKey: string, openid: string, nickname?: string): Candidate | undefined {
    const c = db.candidates.find(x => x.bindKey === bindKey);
    if (c) {
      c.openid = openid;
      if (nickname) c.nickname = nickname;
      c.boundAt = new Date().toISOString();
      persist();
    }
    return c;
  },

  addReminder(r: Reminder): void { db.reminders.push(r); persist(); },
  updateReminder(id: string, patch: Partial<Reminder>): Reminder | undefined {
    const r = db.reminders.find(x => x.id === id);
    if (r) { Object.assign(r, patch); persist(); }
    return r;
  },
  duePending(now: Date): Reminder[] {
    return db.reminders.filter(r => r.status === 'pending' && new Date(r.remindAt) <= now);
  },
};
