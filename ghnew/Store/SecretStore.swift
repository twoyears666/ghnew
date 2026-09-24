import Foundation
import CryptoKit
import Security

/// Device-scoped secret storage.
///
/// On first launch a random 256-bit device number is generated and stored in the
/// app's Keychain (accessible only on this device). A symmetric AES-GCM key is
/// derived from that number (SHA-256) and used to encrypt the GitHub token before
/// it is persisted in UserDefaults. If an older plaintext token is found it is
/// migrated (encrypted) automatically, then the plaintext is removed.
enum SecretStore {
    private static let keyService = "com.twoyears666.ghnew"
    private static let deviceAccount = "deviceNumber"
    private static let tokenEncKey = "ghTokenEnc"
    private static let tokenLegacyKey = "ghToken"

    // MARK: - Token

    /// Loads and decrypts the stored token. If only a legacy plaintext token
    /// exists, migrates it to the encrypted form.
    static func loadToken() -> String? {
        if let blob = UserDefaults.standard.string(forKey: tokenEncKey) {
            return decrypt(blob)
        }
        if let legacy = UserDefaults.standard.string(forKey: tokenLegacyKey), !legacy.isEmpty {
            storeToken(legacy)
            UserDefaults.standard.removeObject(forKey: tokenLegacyKey)
            return legacy
        }
        return nil
    }

    /// Encrypts `token` with the device key and stores it.
    static func storeToken(_ token: String) {
        guard let blob = encrypt(token) else {
            UserDefaults.standard.removeObject(forKey: tokenEncKey)
            return
        }
        UserDefaults.standard.set(blob, forKey: tokenEncKey)
    }

    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenEncKey)
        UserDefaults.standard.removeObject(forKey: tokenLegacyKey)
    }

    // MARK: - Device number (256-bit, Keychain)

    static func deviceNumber() -> Data {
        if let existing = loadDeviceNumber() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Extremely unlikely; fall back to a deterministic-per-install value.
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: 0...255)
            }
        }
        let data = Data(bytes)
        saveDeviceNumber(data)
        return data
    }

    private static func loadDeviceNumber() -> Data? {
        loadFromKeychain(account: deviceAccount)
    }

    private static func saveDeviceNumber(_ data: Data) {
        deleteFromKeychain(account: deviceAccount)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: deviceAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - Keychain primitives

    private static func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    private static func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Encryption

    /// Blob layout: version byte (0x01) + sealed box (nonce || tag || ciphertext).
    private static func encrypt(_ token: String) -> String? {
        guard let data = token.data(using: .utf8) else { return nil }
        let key = SymmetricKey(data: SHA256.hash(data: deviceNumber()))
        let sealed: AES.GCM.SealedBox
        do { sealed = try AES.GCM.seal(data, using: key) }
        catch { return nil }
        var blob = Data([0x01])
        guard let combined = sealed.combined else { return nil }
        blob.append(combined)
        return blob.base64EncodedString()
    }

    private static func decrypt(_ base64: String) -> String? {
        guard let blob = Data(base64Encoded: base64), blob.count > 1, blob[0] == 0x01 else { return nil }
        let key = SymmetricKey(data: SHA256.hash(data: deviceNumber()))
        do {
            let sealed = try AES.GCM.SealedBox(combined: blob.dropFirst())
            guard let opened = try? AES.GCM.open(sealed, using: key) else { return nil }
            return String(data: opened, encoding: .utf8)
        } catch {
            return nil
        }
    }
}