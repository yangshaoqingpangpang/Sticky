import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import { config } from './config.js';

const APPLE_ISS = 'https://appleid.apple.com';
const appleJWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const sessionSecret = new TextEncoder().encode(config.jwtSecret);

/** 验证 Sign in with Apple 的 identityToken，返回稳定用户标识 sub（= ownerId） */
export async function verifyAppleIdentityToken(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, appleJWKS, {
    issuer: APPLE_ISS,
    audience: config.appleBundleId,
  });
  if (!payload.sub) throw new Error('Apple token 缺少 sub');
  return payload.sub;
}

/** 签发后端会话 JWT（app 后续请求用它，避免反复验 Apple token） */
export async function issueSession(ownerId: string): Promise<string> {
  return new SignJWT({ ownerId })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(sessionSecret);
}

/** 校验后端会话，返回 ownerId */
export async function verifySession(token: string): Promise<string> {
  const { payload } = await jwtVerify(token, sessionSecret);
  const ownerId = payload.ownerId;
  if (typeof ownerId !== 'string') throw new Error('会话缺少 ownerId');
  return ownerId;
}
