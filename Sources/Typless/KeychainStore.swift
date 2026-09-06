import Foundation
import Security

enum KeychainError: LocalizedError {
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      SecCopyErrorMessageString(status, nil) as String?
        ?? "Keychain error \(status)"
    }
  }
}

struct APIKeyStore {
  private let service = "com.typless.Typless"
  private let account = "OpenAICompatibleAPIKey"

  func load() throws -> String {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return ""
    }
    guard status == errSecSuccess, let data = item as? Data else {
      throw KeychainError.unexpectedStatus(status)
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  func save(_ value: String) throws {
    if value.isEmpty {
      try delete()
      return
    }

    let data = Data(value.utf8)
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let attributes: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(updateStatus)
    }

    var item = query
    for (key, value) in attributes {
      item[key] = value
    }
    let addStatus = SecItemAdd(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(addStatus)
    }
  }

  func delete() throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
