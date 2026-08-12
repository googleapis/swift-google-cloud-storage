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
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import GoogleCloudGax

extension StorageClient {
  /// Reads (downloads) an object from Cloud Storage as an async sequence of Data chunks.
  ///
  /// - Parameters:
  ///   - bucket: The GCS bucket name.
  ///   - object: The GCS object name.
  ///   - options: Configuration options for the read operation.
  /// - Returns: A `ReadObjectResult` containing initial object metadata and streaming body sequence.
  public func readObject(
    from bucket: String,
    object: String,
    options: ReadObjectOptions = .init()
  ) async throws -> ReadObjectResult {
    // TODO(#219): validate range upon construction
    if case .bounded(let start, let end) = options.range {
      guard start <= end else {
        throw DownloadError.invalidRangeHeader("Range start (\(start)) must be <= end (\(end)).")
      }
    }

    let request = try await inner.buildReadObjectRequest(
      bucket: bucket, object: object, options: options)
    let (data, response) = try await inner.data(for: request)

    guard (200..<300).contains(response.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? ""
      throw DownloadError.unexpectedServerResponse(
        statusCode: response.statusCode, message: message)
    }

    let metadata = try Self.parseReadObjectMetadata(
      from: response, bucket: bucket, object: object)

    let stream = AsyncThrowingStream<Data, Error> { continuation in
      if case .prefix(0) = options.range {
        // Requested 0 bytes
      } else if case .suffix(0) = options.range {
        // Requested 0 bytes
      } else if !data.isEmpty {
        continuation.yield(data)
      }
      continuation.finish()
    }

    let sequence = ReadObjectSequence().with {
      $0.bucket = bucket
      $0.object = object
      $0.options = options
      $0.stream = stream
    }
    return ReadObjectResult().with {
      $0.metadata = metadata
      $0.body = sequence
    }
  }

  fileprivate static func parseReadObjectMetadata(
    from response: HTTPURLResponse,
    bucket: String,
    object: String
  ) throws -> ReadObjectMetadata {
    var metadata = ReadObjectMetadata()
    metadata.bucket = bucket
    metadata.object = object

    if let contentRangeHeader = response.value(forHTTPHeaderField: "Content-Range") {
      let contentRange = try HttpContentRange.parse(contentRangeHeader)
      if let total = contentRange.totalSize {
        metadata.size = total
      }
    } else if let sizeStr = response.value(forHTTPHeaderField: "x-goog-stored-content-length")
      ?? response.value(forHTTPHeaderField: "Content-Length"),
      let size = UInt64(sizeStr)
    {
      metadata.size = size
    }

    if let genStr = response.value(forHTTPHeaderField: "x-goog-generation"),
      let gen = UInt64(genStr)
    {
      metadata.generation = gen
    }

    if let metaGenStr = response.value(forHTTPHeaderField: "x-goog-metageneration"),
      let metaGen = UInt64(metaGenStr)
    {
      metadata.metageneration = metaGen
    }

    metadata.etag = response.value(forHTTPHeaderField: "ETag")
    metadata.contentType = response.value(forHTTPHeaderField: "Content-Type")
    metadata.contentEncoding = response.value(forHTTPHeaderField: "Content-Encoding")
    metadata.contentDisposition = response.value(forHTTPHeaderField: "Content-Disposition")
    metadata.storageClass = response.value(forHTTPHeaderField: "x-goog-storage-class")

    if let hashHeader = response.value(forHTTPHeaderField: "x-goog-hash") {
      let (crc, md5) = parseGoogHash(hashHeader)
      metadata.crc32c = crc
      metadata.md5Hash = md5
    }
    if metadata.md5Hash == nil,
      let contentMd5 = response.value(forHTTPHeaderField: "Content-MD5")
    {
      metadata.md5Hash = contentMd5
    }

    if let dateStr = response.value(forHTTPHeaderField: "Last-Modified")
      ?? response.value(forHTTPHeaderField: "Date")
      ?? response.value(forHTTPHeaderField: "x-goog-date")
    {
      metadata.updated = parseHTTPDate(dateStr)
    }

    return metadata
  }

  fileprivate static func parseGoogHash(_ headerValue: String) -> (crc32c: String?, md5: String?) {
    var crc32c: String?
    var md5: String?
    let parts = headerValue.split(separator: ",")
    for part in parts {
      let trimmed = part.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("crc32c=") {
        crc32c = String(trimmed.dropFirst("crc32c=".count))
      } else if trimmed.hasPrefix("md5=") {
        md5 = String(trimmed.dropFirst("md5=".count))
      }
    }
    return (crc32c, md5)
  }

  fileprivate static func parseHTTPDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let date = formatter.date(from: string) {
      return date
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: string) {
      return date
    }
    isoFormatter.formatOptions = [.withInternetDateTime]
    return isoFormatter.date(from: string)
  }
}

extension HTTPClient {
  fileprivate func buildReadObjectRequest(
    bucket: String,
    object: String,
    options: ReadObjectOptions
  ) async throws -> URLRequest {
    var queryItems = [URLQueryItem(name: "alt", value: "media")]

    if let generation = options.generation {
      queryItems.append(URLQueryItem(name: "generation", value: String(generation)))
    }
    if let preconditions = options.preconditions {
      queryItems.append(contentsOf: preconditions.queryItems)
    }

    let allowedObjectCharacters = CharacterSet.urlPathAllowed.subtracting(
      CharacterSet(charactersIn: "/"))
    let encodedObject =
      object.addingPercentEncoding(withAllowedCharacters: allowedObjectCharacters) ?? object
    let encodedBucket =
      bucket.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bucket
    var request = try await self.Request(
      percentEncodedPath: "/storage/v1/b/\(encodedBucket)/o/\(encodedObject)", query: queryItems)
    request.httpMethod = "GET"

    if let rangeHeader = options.range.headerValue {
      request.setValue(rangeHeader, forHTTPHeaderField: "Range")
    }

    request.applyCustomerSuppliedEncryptionHeaders(options.customerEncryptionKey)

    return request
  }
}
