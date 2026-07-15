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
@testable import GoogleCloudStorage
import Testing

#if IntegrationTests

  @Suite struct StorageClientIntegrationTests {
    @Test func testFileUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
      let objectName = "test-upload-\(UUID().uuidString).txt"

      let content = "Hello Google Cloud Storage from Swift!"
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
      try content.write(to: fileURL, atomically: true, encoding: .utf8)
      defer {
        try? FileManager.default.removeItem(at: fileURL)
      }

      let storage = try StorageClient()
      let task = storage.upload(fileURL, to: bucketName, as: objectName)

      var statusUpdates = [UploadStatus]()
      for await status in task.makeStatusStream() {
        statusUpdates.append(status)
        print(
          "Status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
        )
      }

      let object = try await task.value
      #expect(object.bucket == bucketName)
      #expect(object.name == objectName)
      #expect(object.size == Int64(content.utf8.count))
      // Simple Upload - only 1 status update
      #expect(statusUpdates.count == 1)

      print("Upload successful: \(object)")
    }

    @Test func testLargeFileUpload() async throws {
      guard ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"] != nil else {
        Issue.record("GOOGLE_CLOUD_PROJECT environment variable not set")
        return
      }
      let bucketName =
        ProcessInfo.processInfo.environment["GOOGLE_CLOUD_SWIFT_TEST_BUCKET"] ?? "test-bucket"
      let objectName = "test-large-upload-\(UUID().uuidString).bin"

      // 10MB file to trigger resumable upload (threshold is 8MB)
      let fileSize = 10 * 1024 * 1024
      let data = Data(count: fileSize)
      let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(objectName)
      try data.write(to: fileURL)
      defer {
        try? FileManager.default.removeItem(at: fileURL)
      }

      let storage = try StorageClient()
      let task = storage.upload(fileURL, to: bucketName, as: objectName)

      var statusUpdates = [UploadStatus]()
      for await status in task.makeStatusStream() {
        statusUpdates.append(status)
        print(
          "Status: bytes=\(status.bytesUploaded), total=\(status.totalBytes ?? -1), ID=\(status.uploadId ?? "nil")"
        )
      }

      let object = try await task.value
      #expect(object.bucket == bucketName)
      #expect(object.name == objectName)
      #expect(object.size == Int64(fileSize))

      // Verify that it was a resumable upload by checking for upload ID in status updates
      let hasUploadId = statusUpdates.contains { $0.uploadId != nil }
      #expect(hasUploadId)
      // Statuses: Start -> First Chunk -> Final Upload
      #expect(statusUpdates.count == 3)

      print("Large upload successful: \(object)")
    }
  }

#endif
