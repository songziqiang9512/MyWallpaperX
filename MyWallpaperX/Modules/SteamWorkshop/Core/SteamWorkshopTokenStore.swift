//
//  SteamWorkshopTokenStore.swift
//  MyWallpaperX
//

import Foundation
import Security

/// SK2.3：新登录路线（SteamKit）的 Keychain 令牌存储。
///
/// 合同（§3.3）：
/// - refresh token / GuardData 按 Keychain 存（单主账号槽位），原子替换
///   （update 失败且未找到才 add，绝不先删后写）。
/// - UserDefaults 只存非敏感项：显示名、保存时间、记住偏好。
/// - 令牌明文不落日志/UserDefaults/任务历史。
enum SteamWorkshopTokenStore {
    struct Payload: Codable, Equatable {
        var accountName: String
        var refreshToken: String
        var guardData: String?
        var steamId: String
        var savedAt: Date
    }

    enum TokenSaveResult: Equatable {
        case notAttempted
        case saved
        case failed
    }

    static let rememberPreferenceKey = "SteamWorkshop.steamKitRememberLogin"
    static let restoreAuthorizedKey = "SteamWorkshop.steamKitRestoreAuthorized"

    static var isRestoreAuthorized: Bool {
        // Existing saved sessions predate this gate; explicit revocation always stores false.
        UserDefaults.standard.object(forKey: restoreAuthorizedKey) == nil
            || UserDefaults.standard.bool(forKey: restoreAuthorizedKey)
    }

    static let lastAccountNameKey = "SteamWorkshop.steamKitLastAccountName"
    static let lastRestoredAtKey = "SteamWorkshop.steamKitLastRestoredAt"

    /// 仅测试 harness 使用：隔离 Keychain service 名，避免污染真实槽位。
    nonisolated(unsafe) static var serviceOverride: String?

    private static var service: String { serviceOverride ?? "com.songziqiang.MyWallpaperX.steam.token" }
    private static let account = "primarySession"

    /// 原子写入：先 update，未找到才 add；返回是否成功（失败不伪报已保存）。
    @discardableResult
    static func save(_ payload: Payload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var create = query
        create[kSecValueData as String] = data
        return SecItemAdd(create as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> Payload? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// 非敏感展示信息（UserDefaults）。
    static func saveDisplayMetadata(accountName: String) {
        UserDefaults.standard.set(accountName, forKey: lastAccountNameKey)
        UserDefaults.standard.set(Date(), forKey: lastRestoredAtKey)
    }

    static func clearDisplayMetadata() {
        UserDefaults.standard.removeObject(forKey: lastAccountNameKey)
        UserDefaults.standard.removeObject(forKey: lastRestoredAtKey)
    }
}
