import Foundation
import Security

/// Optional API key storage, read once on entry. No credentials in settings or request URLs.
actor WallhavenCredentialStore {
    private let service: String
    init(service: String? = nil) {
        self.service = service ?? (Bundle.main.bundleIdentifier ?? "com.MyWallpaperX") + ".wallhaven"
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }
    func read() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw failure(status) }
        return value
    }
    func write(_ value: String?) throws {
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure(status) }
        var create = query; create[kSecValueData as String] = data
        let added = SecItemAdd(create as CFDictionary, nil)
        guard added == errSecSuccess else { throw failure(added) }
    }
    private func failure(_ status: OSStatus) -> Error {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "无法读写 Wallhaven API Key，请检查钥匙串权限。"])
    }
}
