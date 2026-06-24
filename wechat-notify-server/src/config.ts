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
  // Sign in with Apple：identityToken 的 aud 必须等于 app 的 bundle id
  appleBundleId: process.env.APPLE_BUNDLE_ID ?? 'com.yangshaoqing.sticky',
  // 后端会话 JWT 签名密钥（生产务必改成随机长串）
  jwtSecret: process.env.JWT_SECRET ?? 'dev-secret-change-me',
  dataFile: process.env.DATA_FILE ?? './data/store.json',
  detailBaseUrl: process.env.DETAIL_BASE_URL ?? '', // 模板消息点击跳转(可空)
};

/** 微信资质是否齐全；未齐时后端可启动用于联调，但不真正下发 */
export function wechatConfigured(): boolean {
  const w = config.wechat;
  return !!(w.appId && w.appSecret && w.token && w.templateId);
}
