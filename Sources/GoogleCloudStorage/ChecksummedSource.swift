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

struct ChunkInfo: Sendable {
  let data: Data
  let isLast: Bool
  let checksum: String?
}

struct ChecksummedSource<S: UploadSource> {
  var source: S
  let validation: ChecksumValidation
  private var md5 = Insecure.MD5()
  private var crc32c = CRC32C()
  private var nextChunk: Data? = nil
  private var isInitialized = false
  private var isFinished = false

  init(source: S, validation: ChecksumValidation) {
    self.source = source
    self.validation = validation
  }

  mutating func readChunk(maxBytes: Int) async throws -> ChunkInfo? {
    if !isInitialized {
      nextChunk = try await source.read(maxBytes: maxBytes)
      isInitialized = true
    }

    guard let currentChunk = nextChunk, !currentChunk.isEmpty else {
      return nil
    }

    nextChunk = try await source.read(maxBytes: maxBytes)
    let isLast = nextChunk == nil || nextChunk!.isEmpty

    var checksumStr: String? = nil
    if validation != .none {
      switch validation {
      case .crc32c:
        crc32c.update(currentChunk)
        if isLast {
          let bigEndian = crc32c.finalize().bigEndian
          var bytes = [UInt8]()
          withUnsafeBytes(of: bigEndian) {
            bytes = Array($0)
          }
          checksumStr = "crc32c=" + Data(bytes).base64EncodedString()
          isFinished = true
        }
      case .md5:
        md5.update(data: currentChunk)
        if isLast {
          let digest = md5.finalize()
          checksumStr = "md5=" + Data(digest).base64EncodedString()
          isFinished = true
        }
      case .none:
        break
      }
    }

    return ChunkInfo(data: currentChunk, isLast: isLast, checksum: checksumStr)
  }
}
