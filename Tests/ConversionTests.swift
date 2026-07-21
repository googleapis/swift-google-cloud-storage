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

import GoogleCloudGax
@testable import GoogleCloudStorage
import StorageControlProtos
import Testing

@Suite struct ConversionTests {
  @Test func findingCategoryKnownValueRoundtrip() throws {
    // Round-trip .dataManagement
    let native = FindingCategory.dataManagement
    let proto = try native.toProto()
    #expect(proto == .dataManagement)

    let roundtripped = FindingCategory(proto: proto)
    #expect(roundtripped == native)
  }

  @Test func findingCategoryProtoToNativeUnknownInteger() throws {
    // Proto UNRECOGNIZED(42) -> Native .unknownIntValue(42)
    let proto = StorageControlProtos.Google_Storage_Control_V2_FindingCategory.UNRECOGNIZED(42)
    let native = FindingCategory(proto: proto)
    #expect(native == .unknownIntValue(42))
  }

  @Test func findingCategoryNativeToProtoUnknownInteger() throws {
    // Native .unknownIntValue(42) -> Proto UNRECOGNIZED(42)
    let native = FindingCategory.unknownIntValue(42)
    let proto = try native.toProto()
    #expect(proto == .UNRECOGNIZED(42))
  }

  @Test func findingCategoryNativeToProtoUnknownStringThrows() throws {
    // Native .unknownStringValue("NEW_CATEGORY") -> throws noIntegerValue
    let native = FindingCategory.unknownStringValue("NEW_CATEGORY")
    #expect(
      throws: ProtobufConversionError.noIntegerValue(
        enumType: "FindingCategory", stringValue: "NEW_CATEGORY")
    ) {
      _ = try native.toProto()
    }
  }

  @Test func pendingRenameInfoRoundtrip() throws {
    let original = PendingRenameInfo().with {
      $0.operation = "projects/_/buckets/my-bucket/operations/12345"
    }

    let proto = try original.toProto()
    #expect(proto.operation == "projects/_/buckets/my-bucket/operations/12345")

    let roundtripped = try PendingRenameInfo(proto: proto)
    #expect(original == roundtripped)
  }
}
