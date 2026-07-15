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
// See the License for theing specific language governing permissions and
// limitations under the License.

import Foundation
import GoogleCloudGax
@testable import GoogleCloudStorage
import Testing

@Suite struct RangeHeaderTests {
  @Test func parseRangeHeader() throws {
    let httpClient = try GoogleCloudGax.HTTPClient(
      from: .init(), withDefaultEndpoint: "https://example.com")

    // Valid full range
    let range1 = try httpClient.parseRangeHeader("bytes=0-1999")
    #expect(range1.start == 0)
    #expect(range1.end == 1999)

    // Valid start only
    let range2 = try httpClient.parseRangeHeader("bytes=2000-")
    #expect(range2.start == 2000)
    #expect(range2.end == nil)

    // Valid end only
    let range3 = try httpClient.parseRangeHeader("bytes=-2000")
    #expect(range3.start == nil)
    #expect(range3.end == 2000)

    // Invalid prefix
    #expect(throws: UploadError.self) {
      _ = try httpClient.parseRangeHeader("foo=0-1999")
    }

    // Invalid format
    #expect(throws: UploadError.self) {
      _ = try httpClient.parseRangeHeader("bytes=abc-def")
    }

    #expect(throws: UploadError.self) {
      _ = try httpClient.parseRangeHeader("bytes=-")
    }

    #expect(throws: UploadError.self) {
      _ = try httpClient.parseRangeHeader("bytes=2000-1000")
    }
  }

  @Test func parseNextRangeStart() throws {
    let httpClient = try GoogleCloudGax.HTTPClient(
      from: .init(), withDefaultEndpoint: "https://example.com")

    #expect(try httpClient.parseNextRangeStart("bytes=0-1999") == 2000)

    #expect(throws: UploadError.self) {
      _ = try httpClient.parseNextRangeStart("bytes=2000-")
    }

    #expect(try httpClient.parseNextRangeStart("bytes=-2000") == 2001)

    #expect(throws: UploadError.self) {
      _ = try httpClient.parseNextRangeStart("bytes=abc-def")
    }
  }
}
