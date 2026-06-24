import Foundation
import AuthenticationServices

// MARK: - Keychain（存后端会话令牌等敏感数据）

enum WXKeychain {
    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}

// MARK: - 后端 API 客户端

struct WeChatBackend {
    let base: URL
    var session: String?

    struct AuthResp: Decodable { let ownerId: String; let sessionToken: String }
    struct Candidate: Decodable, Identifiable {
        let id: String; let name: String; let openid: String?; let boundAt: String?
        var isBound: Bool { openid != nil }
    }
    struct BindQrResp: Decodable { let candidate: Candidate; let qrUrl: String? }
    struct ReminderResp: Decodable { let id: String; let status: String }

    func authApple(identityToken: String) async throws -> AuthResp {
        try await send("/api/auth/apple", method: "POST", body: ["identityToken": identityToken], authed: false)
    }
    func bindQr(name: String) async throws -> BindQrResp {
        try await send("/api/candidates/bind-qr", method: "POST", body: ["name": name], authed: true)
    }
    func candidates() async throws -> [Candidate] {
        try await send("/api/candidates", method: "GET", body: nil, authed: true)
    }
    func createReminder(candidateId: String, text: String, remindAt: Date) async throws -> ReminderResp {
        let iso = ISO8601DateFormatter().string(from: remindAt)
        return try await send("/api/reminders", method: "POST",
                              body: ["candidateId": candidateId, "text": text, "remindAt": iso], authed: true)
    }

    private func send<T: Decodable>(_ path: String, method: String, body: [String: String]?, authed: Bool) async throws -> T {
        var s = base.absoluteString
        if s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s + path) else { throw err("后端地址无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed, let session { req.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw err(msg?["error"] as? String ?? "请求失败(\(code))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func err(_ m: String) -> NSError { NSError(domain: "WeChatBackend", code: -1, userInfo: [NSLocalizedDescriptionKey: m]) }
}

// MARK: - 登录态管理（Sign in with Apple → 换后端会话）

@MainActor
final class AuthManager: ObservableObject {
    @Published var ownerId: String? = WXKeychain.get("wx_ownerId")
    @Published var isAuthing = false
    @Published var lastError: String?

    var sessionToken: String? { WXKeychain.get("wx_session") }
    var isLoggedIn: Bool { ownerId != nil && sessionToken != nil }

    /// 处理 SignInWithAppleButton 的回调，拿 identityToken 换后端会话
    func handle(_ result: Result<ASAuthorization, Error>, backendURL: String) {
        switch result {
        case .failure(let e):
            lastError = e.localizedDescription
        case .success(let authz):
            guard let cred = authz.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                lastError = "未获取到 Apple identityToken"; return
            }
            let trimmed = backendURL.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
                lastError = "请先在上方填写后端地址"; return
            }
            isAuthing = true; lastError = nil
            Task { await exchange(token: token, base: url) }
        }
    }

    private func exchange(token: String, base: URL) async {
        do {
            let res = try await WeChatBackend(base: base, session: nil).authApple(identityToken: token)
            WXKeychain.set("wx_session", res.sessionToken)
            WXKeychain.set("wx_ownerId", res.ownerId)
            ownerId = res.ownerId
            isAuthing = false
        } catch {
            isAuthing = false
            lastError = (error as NSError).localizedDescription
        }
    }

    func signOut() {
        WXKeychain.delete("wx_session")
        WXKeychain.delete("wx_ownerId")
        ownerId = nil
        lastError = nil
    }

    /// owner ID 脱敏展示
    var maskedOwner: String {
        guard let o = ownerId, o.count > 8 else { return ownerId ?? "" }
        return String(o.prefix(6)) + "…" + String(o.suffix(4))
    }
}
