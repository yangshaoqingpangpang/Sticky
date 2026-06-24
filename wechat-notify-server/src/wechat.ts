import axios from 'axios';
import crypto from 'crypto';
import { config } from './config.js';

const API = 'https://api.weixin.qq.com';

let cachedToken = '';
let tokenExpiry = 0;

/** access_token：内存缓存 + 到期前刷新 */
export async function getAccessToken(): Promise<string> {
  if (cachedToken && Date.now() < tokenExpiry - 60_000) return cachedToken;
  const { appId, appSecret } = config.wechat;
  const url = `${API}/cgi-bin/token?grant_type=client_credential&appid=${appId}&secret=${appSecret}`;
  const { data } = await axios.get(url);
  if (!data.access_token) throw new Error(`获取 access_token 失败: ${JSON.stringify(data)}`);
  cachedToken = data.access_token;
  tokenExpiry = Date.now() + data.expires_in * 1000;
  return cachedToken;
}

/** 生成带参二维码（绑定用），返回可直接展示的图片 URL */
export async function createBindQr(
  sceneStr: string,
  expireSeconds = 2_592_000, // 30 天
): Promise<{ ticket: string; qrUrl: string }> {
  const token = await getAccessToken();
  const { data } = await axios.post(`${API}/cgi-bin/qrcode/create?access_token=${token}`, {
    expire_seconds: expireSeconds,
    action_name: 'QR_STR_SCENE',
    action_info: { scene: { scene_str: sceneStr } },
  });
  if (!data.ticket) throw new Error(`创建带参二维码失败: ${JSON.stringify(data)}`);
  return {
    ticket: data.ticket,
    qrUrl: `https://mp.weixin.qq.com/cgi-bin/showqrcode?ticket=${encodeURIComponent(data.ticket)}`,
  };
}

/** 发送模板消息 */
export async function sendTemplate(
  openid: string,
  data: Record<string, { value: string; color?: string }>,
  url?: string,
): Promise<void> {
  const token = await getAccessToken();
  const body: Record<string, unknown> = { touser: openid, template_id: config.wechat.templateId, data };
  if (url) body.url = url;
  const res = await axios.post(`${API}/cgi-bin/message/template/send?access_token=${token}`, body);
  if (res.data.errcode !== 0) throw new Error(`模板消息发送失败: ${JSON.stringify(res.data)}`);
}

/** 回调签名校验：sha1(sort(token,timestamp,nonce)) === signature */
export function verifySignature(signature?: string, timestamp?: string, nonce?: string): boolean {
  if (!signature || !timestamp || !nonce) return false;
  const arr = [config.wechat.token, timestamp, nonce].sort();
  const sha1 = crypto.createHash('sha1').update(arr.join('')).digest('hex');
  return sha1 === signature;
}

/** 微信回调 XML 字段简单，正则解析即可（兼容 CDATA 与纯文本） */
export function parseXml(xml: string): Record<string, string> {
  const out: Record<string, string> = {};
  const re = /<(\w+)><!\[CDATA\[([\s\S]*?)\]\]><\/\1>|<(\w+)>([\s\S]*?)<\/\3>/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(xml))) {
    const k = m[1] ?? m[3];
    const v = m[2] ?? m[4];
    if (k) out[k] = v;
  }
  return out;
}
