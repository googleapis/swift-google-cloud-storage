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
@testable import GoogleCloudStorage
import Testing

@Suite struct ResumableUploadTests {
  // Mock UploadSource that can throw errors
  struct MockUploadSource: SeekableUploadSource {
    var data: Data
    var totalSize: Int64?
    var readError: Error?
    var seekError: Error?
    private var offset: Int64 = 0

    init(data: Data, totalSize: Int64? = nil, readError: Error? = nil, seekError: Error? = nil) {
      self.data = data
      self.totalSize = totalSize ?? Int64(data.count)
      self.readError = readError
      self.seekError = seekError
    }

    mutating func read(maxBytes: Int) async throws -> Data? {
      if let error = readError {
        throw error
      }
      guard offset < data.count else { return nil }
      let end = min(offset + Int64(maxBytes), Int64(data.count))
      let chunk = data.subdata(in: Int(offset)..<Int(end))
      offset = end
      return chunk
    }

    mutating func seek(to offset: Int64) async throws {
      if let error = seekError {
        throw error
      }
      guard offset >= 0 && offset <= data.count else {
        throw UploadError.internalError("Invalid seek offset: \(offset)")
      }
      self.offset = offset
    }
  }

  @Test func resumableUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let objectJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: objectJSON.data(using: .utf8)!,
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  @Test func resumableUploadSourceReadError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, readError: DummyError())

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    await #expect(throws: DummyError.self) {
      _ = try await task.value
    }
  }

  @Test func resumableUploadNetworkError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")

    registry.register(
      response: .failure(URLError(.cannotConnectToHost)),
      for: startUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    await #expect(throws: URLError.self) {
      _ = try await task.value
    }
  }

  @Test func resumableUploadHTTPError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let startUrl = registry.url(
      "/upload/storage/v1/b/\(bucket)/o?uploadType=resumable&name=\(objectName)")
    let chunkUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 200, data: Data(),
        headers: ["Location": chunkUrl.absoluteString]),
      for: startUrl)
    registry.register(
      response: .success(
        statusCode: 500, data: "Internal Server Error".data(using: .utf8)!,
        headers: nil),
      for: chunkUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.upload(source, to: bucket, as: objectName)

    await #expect(throws: UploadError.self) {
      _ = try await task.value
    }
  }

  @Test func resumeUploadSuccess() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let objectName = "test-object"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    let source = BytesSource(data: data)

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    let objectJSON = """
      {
        "name": "\(objectName)",
        "bucket": "\(bucket)",
        "generation": "1",
        "metageneration": "1",
        "size": "\(data.count)",
        "contentType": "application/octet-stream",
        "storageClass": "STANDARD"
      }
      """

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-4999"]),
      for: queryUrl)
    registry.register(
      response: .success(
        statusCode: 200, data: objectJSON.data(using: .utf8)!,
        headers: nil),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)
    let object = try await task.value

    #expect(object.name == objectName)
    #expect(object.bucket == bucket)
  }

  @Test func resumeUploadSourceSeekError() async throws {
    let registry = MockRegistry.create()
    let bucket = "test-bucket"
    let data = Data(repeating: 1, count: 10 * 1024 * 1024)  // 10MB
    struct DummyError: Error {}
    let source = MockUploadSource(data: data, seekError: DummyError())

    let queryUrl = registry.url("/upload/storage/v1/b/\(bucket)/o?upload_id=test-id")

    registry.register(
      response: .success(
        statusCode: 308, data: Data(),
        headers: ["Range": "bytes=0-4999"]),
      for: queryUrl)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)

    let options = StorageClientOptions().with {
      $0.client = .init().with {
        $0.endpoint = registry.endpoint
        $0._testSession = session
      }
    }

    let client = try StorageClient(options)
    let task = client.resumeUpload(source, uploadId: queryUrl.absoluteString)

    await #expect(throws: DummyError.self) {
      _ = try await task.value
    }
  }
}
