// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Crypto
import Foundation
import GoogleCloudWkt

/// Strategy for data integrity validation.
public enum ChecksumValidation: Sendable {
  /// Do not perform client-side checksum validation.
  case none

  /// Automatically calculate and validate CRC32C (recommended).
  case crc32c

  /// Automatically calculate and validate MD5.
  case md5
}

/// Configuration options for upload checksum validation.
public struct ChecksumOptions: Sendable, Hashable {
  /// Checksum mode / value for CRC32C.
  public var crc32c: ChecksumValue?

  /// Checksum mode / value for MD5.
  public var md5: ChecksumValue?

  /// Specifies how a checksum should be provided for upload validation.
  public enum ChecksumValue: Sendable, Hashable, ExpressibleByStringLiteral {
    /// Automatically calculate the checksum on-the-fly during upload streaming.
    case auto

    /// Use a pre-computed checksum value (e.g., Base64 encoded string).
    case value(String)

    /// Creates a `ChecksumValue` from a string literal containing a pre-computed checksum.
    public init(stringLiteral value: String) {
      self = .value(value)
    }
  }

  /// Creates a new `ChecksumOptions` configuration for validating uploads with Google Cloud Storage.
  ///
  /// You can configure automatic on-the-fly calculation (`.auto`), pre-computed values (e.g., `.value("...")` or a string literal `"..."`),
  /// or enable multiple checksum types simultaneously in a single upload request. `crc32c` is the default and recommended checksum option,
  /// as it provides better computational performance compared to MD5.
  public init(crc32c: ChecksumValue? = .auto, md5: ChecksumValue? = nil) {
    self.crc32c = crc32c
    self.md5 = md5
  }

  /// Default options: Automatically calculate CRC32C on-the-fly.
  public static var `default`: ChecksumOptions {
    ChecksumOptions(crc32c: .auto, md5: nil)
  }

  /// No checksum validation.
  public static var none: ChecksumOptions {
    ChecksumOptions(crc32c: nil, md5: nil)
  }

  public var hasUserProvidedChecksum: Bool {
    if case .value = crc32c { return true }
    if case .value = md5 { return true }
    return false
  }
}

/// Errors thrown when validating or creating a `CustomerEncryptionKeyOptions`.
public enum CustomerEncryptionKeyError: Error, Sendable, Equatable,
  CustomStringConvertible
{
  /// The key length in bytes does not match the expected length required by the algorithm.
  case invalidKeyLength(actual: Int, expected: Int)

  /// The provided key string is not a valid Base64-encoded string.
  case invalidBase64Key

  public var description: String {
    switch self {
    case .invalidKeyLength(let actual, let expected):
      return
        "Invalid customer encryption key length: got \(actual) bytes, expected \(expected) bytes."
    case .invalidBase64Key:
      return "Customer encryption key is not a valid base64-encoded string."
    }
  }
}

/// Options for [Customer-Supplied Encryption Keys] (CSEK).
///
/// As an additional layer on top of [standard Cloud Storage encryption], you can choose to provide
/// your own AES-256 encryption key, encoded in [standard Base64]. This key is known as a
/// customer-supplied encryption key. If you provide a customer-supplied encryption key,
/// Cloud Storage does not permanently store your key in its servers or otherwise manage your key.
///
/// Encryption algorithm used for Customer-Supplied Encryption Keys (CSEK).
public enum CustomerEncryptionAlgorithm: String, Sendable, Equatable, CustomStringConvertible {
  /// AES-256 encryption algorithm (default and currently the only supported algorithm in Cloud Storage).
  case aes256 = "AES256"

  public var description: String {
    rawValue
  }
}

/// Options for [Customer-Supplied Encryption Keys] (CSEK).
///
/// As an additional layer on top of [standard Cloud Storage encryption], you can choose to provide
/// your own AES-256 encryption key, encoded in [standard Base64]. This key is known as a
/// customer-supplied encryption key. If you provide a customer-supplied encryption key,
/// Cloud Storage does not permanently store your key in its servers or otherwise manage your key.
///
/// [standard Cloud Storage encryption]: https://docs.cloud.google.com/storage/docs/encryption/default-keys
/// [standard Base64]: https://datatracker.ietf.org/doc/html/rfc4648#section-4
/// [Customer-Supplied Encryption Keys]: https://docs.cloud.google.com/storage/docs/encryption/customer-supplied-keys
public struct CustomerEncryptionKeyOptions: Sendable, Equatable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  /// The encryption algorithm used (e.g. `.aes256`).
  public let algorithm: CustomerEncryptionAlgorithm

  /// The raw symmetric key material.
  public let key: SymmetricKey

  public static func == (lhs: CustomerEncryptionKeyOptions, rhs: CustomerEncryptionKeyOptions)
    -> Bool
  {
    lhs.algorithm == rhs.algorithm && lhs.key == rhs.key
  }

  /// The Base64-encoded string representation of the encryption key.
  public var keyBase64: String {
    key.withUnsafeBytes { Data($0).base64EncodedString() }
  }

  /// The Base64-encoded SHA-256 digest of the key material used for header validation.
  public var keyHashBase64: String {
    let data = key.withUnsafeBytes { Data($0) }
    let hash = SHA256.hash(data: data)
    return Data(hash).base64EncodedString()
  }

  public var description: String {
    "CustomerEncryptionKeyOptions(algorithm: \(algorithm.rawValue), keyHashBase64: \(keyHashBase64))"
  }

  public var debugDescription: String {
    description
  }

  /// Creates a `CustomerEncryptionKeyOptions` from a `SymmetricKey`.
  ///
  /// For the default `.aes256` algorithm, the key must be exactly 32 bytes (256 bits).
  public init(key: SymmetricKey, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    let count = key.withUnsafeBytes { $0.count }
    if algorithm == .aes256 && count != 32 {
      throw CustomerEncryptionKeyError.invalidKeyLength(actual: count, expected: 32)
    }
    self.algorithm = algorithm
    self.key = key
  }

  /// Creates a `CustomerEncryptionKeyOptions` from Apple CryptoKit / Swift Crypto `SymmetricKey`.
  public init(symmetricKey: SymmetricKey, algorithm: CustomerEncryptionAlgorithm = .aes256)
    throws
  {
    try self.init(key: symmetricKey, algorithm: algorithm)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from pre-computed values.
  public init(
    algorithm: CustomerEncryptionAlgorithm = .aes256, keyBase64: String, keyHashBase64: String
  ) {
    let keyData = Data(base64Encoded: keyBase64) ?? Data(keyBase64.utf8)
    self.algorithm = algorithm
    self.key = SymmetricKey(data: keyData)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from raw key bytes (`Data`).
  ///
  /// For the default `.aes256` algorithm, the key must be exactly 32 bytes (256 bits).
  /// The key and its SHA-256 hash are automatically Base64-encoded.
  public init(key: Data, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    if algorithm == .aes256 && key.count != 32 {
      throw CustomerEncryptionKeyError.invalidKeyLength(actual: key.count, expected: 32)
    }
    self.algorithm = algorithm
    self.key = SymmetricKey(data: key)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from raw key bytes (`[UInt8]`).
  public init(keyBytes: [UInt8], algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    try self.init(key: Data(keyBytes), algorithm: algorithm)
  }

  /// Creates a `CustomerEncryptionKeyOptions` from a Base64-encoded key string.
  ///
  /// For the default `.aes256` algorithm, the decoded key must be exactly 32 bytes (256 bits).
  /// The SHA-256 hash is automatically computed and Base64-encoded.
  public init(keyBase64: String, algorithm: CustomerEncryptionAlgorithm = .aes256) throws {
    guard let keyData = Data(base64Encoded: keyBase64) else {
      throw CustomerEncryptionKeyError.invalidBase64Key
    }
    try self.init(key: keyData, algorithm: algorithm)
  }
}

/// Preconditions for GCS operations.
public struct StoragePreconditions: Sendable {
  /// Makes the operation succeed only if the object's current generation matches this value.
  public var ifGenerationMatch: Int64?

  /// Makes the operation succeed only if the object's current generation does not match this value.
  public var ifGenerationNotMatch: Int64?

  /// Makes the operation succeed only if the object's current metageneration matches this value.
  public var ifMetagenerationMatch: Int64?

  /// Makes the operation succeed only if the object's current metageneration does not match this value.
  public var ifMetagenerationNotMatch: Int64?

  public init(
    ifGenerationMatch: Int64? = nil,
    ifGenerationNotMatch: Int64? = nil,
    ifMetagenerationMatch: Int64? = nil,
    ifMetagenerationNotMatch: Int64? = nil
  ) {
    self.ifGenerationMatch = ifGenerationMatch
    self.ifGenerationNotMatch = ifGenerationNotMatch
    self.ifMetagenerationMatch = ifMetagenerationMatch
    self.ifMetagenerationNotMatch = ifMetagenerationNotMatch
  }
}

extension StoragePreconditions {
  /// Converts non-nil precondition fields into URL query items.
  package var queryItems: [URLQueryItem] {
    var items: [URLQueryItem] = []
    if let ifGenerationMatch {
      items.append(URLQueryItem(name: "ifGenerationMatch", value: String(ifGenerationMatch)))
    }
    if let ifGenerationNotMatch {
      items.append(URLQueryItem(name: "ifGenerationNotMatch", value: String(ifGenerationNotMatch)))
    }
    if let ifMetagenerationMatch {
      items.append(
        URLQueryItem(name: "ifMetagenerationMatch", value: String(ifMetagenerationMatch)))
    }
    if let ifMetagenerationNotMatch {
      items.append(
        URLQueryItem(name: "ifMetagenerationNotMatch", value: String(ifMetagenerationNotMatch)))
    }
    return items
  }
}

/// Represents the metadata of the object to be created.
public struct UploadMetadata: Sendable, Codable {
  /// Content-Type header of the object data (e.g. "application/json", "image/png").
  public var contentType: String?

  /// Content-Encoding header of the object data (e.g. "gzip").
  public var contentEncoding: String?

  /// Content-Disposition header of the object data (e.g. "inline", "attachment; filename=filename.ext").
  public var contentDisposition: String?

  /// Content-Language header of the object data (e.g. "en", "es").
  public var contentLanguage: String?

  /// Cache-Control header of the object data (e.g. "public, max-age=3600").
  public var cacheControl: String?

  /// Custom key-value metadata pairs associated with the object.
  public var customMetadata: [String: String]?

  public init(
    contentType: String? = nil,
    contentEncoding: String? = nil,
    contentDisposition: String? = nil,
    contentLanguage: String? = nil,
    cacheControl: String? = nil,
    customMetadata: [String: String]? = nil
  ) {
    self.contentType = contentType
    self.contentEncoding = contentEncoding
    self.contentDisposition = contentDisposition
    self.contentLanguage = contentLanguage
    self.cacheControl = cacheControl
    self.customMetadata = customMetadata
  }
}

/// Configuration options for the upload request/session.
public struct UploadOptions: Sendable {
  /// The chunk size in bytes for resumable uploads. Defaults to 8 MB (8 * 1024 * 1024).
  public var chunkSize: Int

  /// Preconditions (e.g. `ifGenerationMatch`) for the upload operation.
  public var preconditions: StoragePreconditions?

  /// Resource name of the Cloud KMS key used to encrypt the object (Customer-Managed Encryption Keys / CMEK).
  public var kmsKeyName: String?

  /// Options for Customer-Supplied Encryption Keys (CSEK).
  public var customerEncryptionKey: CustomerEncryptionKeyOptions?

  /// Configuration options for upload checksum validation.
  public var checksums: ChecksumOptions

  /// Legacy validation enum property for backward compatibility.
  public var validation: ChecksumValidation {
    get {
      if checksums.crc32c == .auto && checksums.md5 == nil {
        return .crc32c
      } else if checksums.md5 == .auto && checksums.crc32c == nil {
        return .md5
      } else {
        return .none
      }
    }
    set {
      switch newValue {
      case .none:
        checksums = .none
      case .crc32c:
        checksums = ChecksumOptions(crc32c: .auto, md5: nil)
      case .md5:
        checksums = ChecksumOptions(crc32c: nil, md5: .auto)
      }
    }
  }

  public static var `default`: UploadOptions { UploadOptions() }

  public init(
    chunkSize: Int = 8 * 1024 * 1024,
    preconditions: StoragePreconditions? = nil,
    kmsKeyName: String? = nil,
    customerEncryptionKey: CustomerEncryptionKeyOptions? = nil,
    checksums: ChecksumOptions = .default
  ) {
    self.chunkSize = chunkSize
    self.preconditions = preconditions
    self.kmsKeyName = kmsKeyName
    self.customerEncryptionKey = customerEncryptionKey
    self.checksums = checksums
  }

  public init(
    chunkSize: Int = 8 * 1024 * 1024,
    preconditions: StoragePreconditions? = nil,
    kmsKeyName: String? = nil,
    customerEncryptionKey: CustomerEncryptionKeyOptions? = nil,
    validation: ChecksumValidation
  ) {
    self.chunkSize = chunkSize
    self.preconditions = preconditions
    self.kmsKeyName = kmsKeyName
    self.customerEncryptionKey = customerEncryptionKey
    self.checksums = .none
    self.validation = validation
  }
}

/// Customer encryption metadata returned in object responses.
public struct CustomerEncryption: Sendable, Codable, Equatable {
  /// The encryption algorithm used to encrypt the object (e.g., "AES256").
  public var encryptionAlgorithm: String?

  /// The Base64-encoded SHA-256 hash of the customer-supplied encryption key.
  public var keySha256: String?

  public init(encryptionAlgorithm: String? = nil, keySha256: String? = nil) {
    self.encryptionAlgorithm = encryptionAlgorithm
    self.keySha256 = keySha256
  }
}

/// Represents a GCS Object.
// TODO(#323): Replace with actual generated struct if available.
public struct StorageObject: Sendable, Codable {
  public var bucket: String = String()
  public var name: String = String()
  public var generation: Int64 = Int64()
  public var metageneration: Int64 = Int64()
  public var size: Int64 = Int64()
  public var contentType: String?
  public var customerEncryption: CustomerEncryption?
  public var md5Hash: String?
  public var crc32c: String?
  public var etag: String?
  public var storageClass: String?
  public var timeCreated: GoogleCloudWkt.Timestamp?
  public var updated: GoogleCloudWkt.Timestamp?

  public init() {}

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    bucket = try container.decode(String.self, forKey: .bucket)
    name = try container.decode(String.self, forKey: .name)

    if let genStr = try? container.decode(String.self, forKey: .generation), let gen = Int64(genStr)
    {
      generation = gen
    } else {
      generation = try container.decode(Int64.self, forKey: .generation)
    }

    if let metaStr = try? container.decode(String.self, forKey: .metageneration),
      let meta = Int64(metaStr)
    {
      metageneration = meta
    } else {
      metageneration = try container.decode(Int64.self, forKey: .metageneration)
    }

    if let sizeStr = try? container.decode(String.self, forKey: .size), let s = Int64(sizeStr) {
      size = s
    } else {
      size = try container.decode(Int64.self, forKey: .size)
    }

    contentType = try? container.decode(String.self, forKey: .contentType)
    customerEncryption = try? container.decode(CustomerEncryption.self, forKey: .customerEncryption)
    md5Hash = try? container.decode(String.self, forKey: .md5Hash)
    crc32c = try? container.decode(String.self, forKey: .crc32c)
    etag = try? container.decode(String.self, forKey: .etag)
    storageClass = try? container.decode(String.self, forKey: .storageClass)
    timeCreated = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .timeCreated)
    updated = try? container.decode(GoogleCloudWkt.Timestamp.self, forKey: .updated)
  }

  enum CodingKeys: String, CodingKey {
    case bucket
    case name
    case generation
    case metageneration
    case size
    case contentType
    case customerEncryption
    case md5Hash
    case crc32c
    case etag
    case storageClass
    case timeCreated
    case updated
  }

  /// Use `config` to return a new instance of this object, with some fields updated.
  ///
  /// Commonly used to initialize the value, for example:
  ///
  /// ```
  /// let value = StorageObject().with { $0.name = ... }
  /// ```
  public func with(_ config: (inout Self) -> Void) -> Self {
    var copy = self
    config(&copy)
    return copy
  }
}
