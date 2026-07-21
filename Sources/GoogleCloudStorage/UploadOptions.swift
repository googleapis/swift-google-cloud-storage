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
public struct CustomerEncryptionKey: Sendable {
  public let algorithm: String
  public let keyBase64: String
  public let keyHashBase64: String

  public init(algorithm: String = "AES256", keyBase64: String, keyHashBase64: String) {
    self.algorithm = algorithm
    self.keyBase64 = keyBase64
    self.keyHashBase64 = keyHashBase64
  }
}

/// Preconditions for GCS operations.
public struct StoragePreconditions: Sendable {
  public var ifGenerationMatch: Int64?
  public var ifGenerationNotMatch: Int64?
  public var ifMetagenerationMatch: Int64?
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

/// Represents the metadata of the object to be created.
public struct UploadMetadata: Sendable, Codable {
  public var contentType: String?
  public var contentEncoding: String?
  public var contentDisposition: String?
  public var contentLanguage: String?
  public var cacheControl: String?
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
  public var chunkSize: Int
  public var preconditions: StoragePreconditions?
  public var kmsKeyName: String?
  public var customerEncryptionKey: CustomerEncryptionKey?
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
    customerEncryptionKey: CustomerEncryptionKey? = nil,
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
    customerEncryptionKey: CustomerEncryptionKey? = nil,
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

/// Represents a GCS Object.
// TODO(#323): Replace with actual generated struct if available.
public struct StorageObject: Sendable, Codable {
  public var bucket: String = String()
  public var name: String = String()
  public var generation: Int64 = Int64()
  public var metageneration: Int64 = Int64()
  public var size: Int64 = Int64()
  public var contentType: String?
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
