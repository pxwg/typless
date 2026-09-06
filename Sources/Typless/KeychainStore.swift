import Foundation
import Security

enum KeychainError: LocalizedError {
  case unexpectedStatus(OSStatus)
  case invalidData

  var errorDescription: String? {
    switch self {
    case .invalidData:
      "无法读取已保存的 API Key，请重新保存。"
    case .unexpectedStatus(let status):
      SecCopyErrorMessageString(status, nil) as String?
        ?? "Keychain error \(status)"
    }
  }
}

protocol APIKeyStoring {
  func contains() throws -> Bool
  func load() throws -> String
  func save(_ value: String) throws
  func delete() throws
}

/// Injectable SecItem operations keep tests isolated from the user's Keychain.
struct KeychainOperations {
  var copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching
  var update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate
  var add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd
  var delete: (CFDictionary) -> OSStatus = SecItemDelete
}

struct APIKeyStore: APIKeyStoring {
  // Keep the inactive legacy provider's item separate; never migrate it into Qwen.
  static var qwen: APIKeyStore {
    APIKeyStore(account: "QwenRealtimeAPIKey", accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
  }

  var account = "OpenAICompatibleAPIKey"
  var accessibility: CFString = kSecAttrAccessibleWhenUnlocked
  var operations = KeychainOperations()

  private var identity: [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.typless.Typless", kSecAttrAccount: account]
  }

  func contains() throws -> Bool {
    var query = identity
    query[kSecReturnAttributes] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    let status = operations.copyMatching(query as CFDictionary, nil)
    if status == errSecItemNotFound { return false }
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    return true
  }

  func load() throws -> String {
    var query = identity
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = operations.copyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return ""
    }
    guard status == errSecSuccess else {
      throw KeychainError.unexpectedStatus(status)
    }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
      throw KeychainError.invalidData
    }
    return value
  }

  func save(_ value: String) throws {
    if value.isEmpty {
      try delete()
      return
    }

    let data = Data(value.utf8)
    let query = identity
    let attributes: [CFString: Any] = [
      kSecValueData: data,
      kSecAttrAccessible: accessibility,
    ]

    let updateStatus = operations.update(query as CFDictionary, attributes as CFDictionary)
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
    let addStatus = operations.add(item as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw KeychainError.unexpectedStatus(addStatus)
    }
  }

  func delete() throws {
    let status = operations.delete(identity as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
