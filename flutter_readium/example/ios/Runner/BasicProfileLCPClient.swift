import CommonCrypto
import Foundation
import ReadiumLCP

/// Test-only stand-in for the private EDRLab R2LCPClient. It supports only the LCP basic profile
/// (SHA-256 user key, AES-256-CBC) and does not check signatures or the CRL. Real apps use the
/// licensed framework instead.
final class BasicProfileLCPClient: LCPClient {
  private struct Context {
    let contentKey: Data
  }

  func createContext(jsonLicense: String, hashedPassphrase: LCPPassphraseHash, pemCrl: String) throws -> LCPClientContext {
    guard let license = try? JSONSerialization.jsonObject(with: Data(jsonLicense.utf8)) as? [String: Any],
      let encryption = license["encryption"] as? [String: Any],
      let contentKey = encryption["content_key"] as? [String: Any],
      let encryptedContentKey = (contentKey["encrypted_value"] as? String).flatMap({ Data(base64Encoded: $0) })
    else { throw LCPClientError.contextInvalid }
    guard let userKey = checkedUserKey(license: license, hashedPassphrase: hashedPassphrase) else {
      throw LCPClientError.userKeyCheckInvalid
    }
    guard let key = Self.cbcDecrypt(key: userKey, blob: encryptedContentKey, unpad: true) else {
      throw LCPClientError.contentKeyDecryptError
    }
    return Context(contentKey: key)
  }

  /// Takes IV || ciphertext and returns the plaintext with the PKCS#7 padding left for the toolkit to strip.
  func decrypt(data: Data, using context: LCPClientContext) -> Data? {
    guard let context = context as? Context else { return nil }
    return Self.cbcDecrypt(key: context.contentKey, blob: data, unpad: false)
  }

  func findOneValidPassphrase(jsonLicense: String, hashedPassphrases: [LCPPassphraseHash]) -> LCPPassphraseHash? {
    guard let license = try? JSONSerialization.jsonObject(with: Data(jsonLicense.utf8)) as? [String: Any] else {
      return nil
    }
    return hashedPassphrases.first { checkedUserKey(license: license, hashedPassphrase: $0) != nil }
  }

  private func checkedUserKey(license: [String: Any], hashedPassphrase: String) -> Data? {
    guard let id = license["id"] as? String,
      let encryption = license["encryption"] as? [String: Any],
      let userKeyInfo = encryption["user_key"] as? [String: Any],
      let keyCheck = (userKeyInfo["key_check"] as? String).flatMap({ Data(base64Encoded: $0) }),
      let userKey = Self.hexToData(hashedPassphrase),
      let checked = Self.cbcDecrypt(key: userKey, blob: keyCheck, unpad: true),
      checked == Data(id.utf8)
    else { return nil }
    return userKey
  }

  private static func cbcDecrypt(key: Data, blob: Data, unpad: Bool) -> Data? {
    guard blob.count >= 32, blob.count % kCCBlockSizeAES128 == 0 else { return nil }
    let iv = blob.prefix(kCCBlockSizeAES128)
    let cipherText = blob.dropFirst(kCCBlockSizeAES128)
    var out = Data(count: cipherText.count)
    var written = 0
    let status = out.withUnsafeMutableBytes { outPtr in
      cipherText.withUnsafeBytes { inPtr in
        key.withUnsafeBytes { keyPtr in
          iv.withUnsafeBytes { ivPtr in
            CCCrypt(
              CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
              keyPtr.baseAddress, key.count, ivPtr.baseAddress,
              inPtr.baseAddress, cipherText.count,
              outPtr.baseAddress, outPtr.count, &written)
          }
        }
      }
    }
    guard status == kCCSuccess, written == out.count else { return nil }
    guard unpad else { return out }
    guard let pad = out.last.map(Int.init), (1...kCCBlockSizeAES128).contains(pad) else { return nil }
    return out.dropLast(pad)
  }

  private static func hexToData(_ hex: String) -> Data? {
    guard hex.count % 2 == 0 else { return nil }
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      data.append(byte)
      index = next
    }
    return data
  }
}
