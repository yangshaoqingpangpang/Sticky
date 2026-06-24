import fs from 'fs';
import path from 'path';
import { config } from './config.js';

export interface Candidate {
  id: string;
  ownerId: string;       // 归属的 app 用户(Sign in with Apple 的 sub)
  name: string;          // 备注名（app 内可改）
  bindKey: string;       // 带参二维码 scene_str，扫码后据此绑定 openid
  openid?: string;
  nickname?: string;
  boundAt?: string;
}

export interface Reminder {
  id: string;
  ownerId: string;       // 归属的 app 用户
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
  // —— 多租户：对外读写一律按 ownerId 隔离 ——
  candidatesByOwner: (ownerId: string): Candidate[] => db.candidates.filter(c => c.ownerId === ownerId),
  findCandidateForOwner: (id: string, ownerId: string): Candidate | undefined =>
    db.candidates.find(c => c.id === id && c.ownerId === ownerId),
  reminderForOwner: (id: string, ownerId: string): Reminder | undefined =>
    db.reminders.find(r => r.id === id && r.ownerId === ownerId),
  addCandidate(c: Candidate): void { db.candidates.push(c); persist(); },
  addReminder(r: Reminder): void { db.reminders.push(r); persist(); },

  /** 微信扫码回调据 bindKey 绑定 openid（bindKey 全局唯一，天然带出归属，无需 owner 过滤） */
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

  /** 内部：按 id 找候选人（调度器发送时用，不暴露给 API） */
  findCandidateInternal: (id: string): Candidate | undefined => db.candidates.find(c => c.id === id),
  updateReminder(id: string, patch: Partial<Reminder>): Reminder | undefined {
    const r = db.reminders.find(x => x.id === id);
    if (r) { Object.assign(r, patch); persist(); }
    return r;
  },
  duePending(now: Date): Reminder[] {
    return db.reminders.filter(r => r.status === 'pending' && new Date(r.remindAt) <= now);
  },
};
