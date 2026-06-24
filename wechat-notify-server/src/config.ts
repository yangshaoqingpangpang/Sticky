import dotenv from 'dotenv';
dotenv.config();

export const config = {
  port: Number(process.env.PORT ?? 9528),
  wechat: {
    appId: process.env.WECHAT_APPID ?? '',
    appSecret: process.env.WECHAT_APPSECRET ?? '',
    token: process.env.WECHAT_TOKEN ?? '',          // 回调校验 Token（与公众平台一致）
    templateId: process.env.WECHAT_TEMPLATE_ID ?? '',
  },
  apiKey: process.env.API_KEY ?? 'dev-local-key',   // app↔后端 鉴权
  dataFile: process.env.DATA_FILE ?? './data/store.json',
  detailBaseUrl: process.env.DETAIL_BASE_URL ?? '', // 模板消息点击跳转(可空)
};

/** 微信资质是否齐全；未齐时后端可启动用于联调，但不真正下发 */
export function wechatConfigured(): boolean {
  const w = config.wechat;
  return !!(w.appId && w.appSecret && w.token && w.templateId);
}
