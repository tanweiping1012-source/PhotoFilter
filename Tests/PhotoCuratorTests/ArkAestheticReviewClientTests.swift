import Foundation
import XCTest
@testable import PhotoCurator

final class ArkAestheticReviewClientTests: XCTestCase {
    func testRequestUsesOnlyOpaqueIDsAndInMemoryDataURLs() throws {
        let localRoot = URL(fileURLWithPath: "/Users/example/Private Trip")
        let localPhotoIDs = [
            localRoot.appendingPathComponent("IMG_1234.jpg").path,
            localRoot.appendingPathComponent("IMG_1235.jpg").path,
        ]
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .similarity, groupID: "similar-2"),
            localPhotoIDs: localPhotoIDs,
            requestID: "ark-request-1"
        )
        let previews = [
            ArkAestheticReviewPreview(opaquePhotoID: "photo_001", jpegData: Data([0x01, 0x02])),
            ArkAestheticReviewPreview(opaquePhotoID: "photo_002", jpegData: Data([0x03, 0x04])),
        ]

        let urlRequest = try ArkAestheticReviewClient().makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "not-a-real-secret"
        )
        let body = try XCTUnwrap(urlRequest.httpBody)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(urlRequest.url, ArkConfiguration.responsesURL)
        XCTAssertTrue(bodyText.contains(ArkConfiguration.modelID))
        XCTAssertTrue(bodyText.contains("input_text"))
        XCTAssertTrue(bodyText.contains("input_image"))
        XCTAssertTrue(bodyText.contains("max_output_tokens"))
        XCTAssertTrue(bodyText.contains("\"max_output_tokens\":1600"))
        XCTAssertTrue(bodyText.contains("\"thinking\":{\"type\":\"disabled\"}"))
        XCTAssertTrue(bodyText.contains("reasons 必须包含 1 到 3 条"))
        XCTAssertTrue(bodyText.contains("\"dimensions\""))
        XCTAssertTrue(bodyText.contains("\"summary\""))
        XCTAssertTrue(bodyText.contains("\"tool_choice\":\"required\""))
        XCTAssertTrue(bodyText.contains("\"name\":\"submit_photo_reviews\""))
        XCTAssertTrue(bodyText.contains("\"strict\":true"))
        XCTAssertTrue(bodyText.contains("\"enum\":[\"photo_001\",\"photo_002\"]"))
        XCTAssertTrue(bodyText.contains("photo_001"))
        XCTAssertTrue(bodyText.contains("photo_002"))
        XCTAssertTrue(bodyText.contains("AQI="), "请求必须携带内存中的 JPEG Base64 数据")
        XCTAssertFalse(bodyText.contains("IMG_1234.jpg"))
        XCTAssertFalse(bodyText.contains("Private Trip"))
        XCTAssertFalse(bodyText.contains("file://"))
    }

    func testDecodesAndValidatesACompleteArkResponse() throws {
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .burst, groupID: "burst-7"),
            localPhotoIDs: ["/private/a.jpg", "/private/b.jpg"],
            requestID: "ark-request-2"
        )
        let data = Data("""
        {
          "output": [{
            "type": "reasoning"
          }, {
            "type": "message",
            "content": [{
              "type": "output_text",
              "text": "{\\\"reviews\\\":[{\\\"photo_id\\\":\\\"photo_001\\\",\\\"rank\\\":2,\\\"score\\\":70,\\\"dimensions\\\":{\\\"moment\\\":68,\\\"composition\\\":75,\\\"subject\\\":70,\\\"lighting\\\":72,\\\"storytelling\\\":65},\\\"reasons\\\":[\\\"构图完整\\\"],\\\"summary\\\":\\\"构图稳定，但瞬间和叙事相对普通。\\\"},{\\\"photo_id\\\":\\\"photo_002\\\",\\\"rank\\\":1,\\\"score\\\":92,\\\"dimensions\\\":{\\\"moment\\\":95,\\\"composition\\\":90,\\\"subject\\\":94,\\\"lighting\\\":89,\\\"storytelling\\\":92},\\\"reasons\\\":[\\\"瞬间更自然\\\",\\\"主体更突出\\\"],\\\"summary\\\":\\\"主体和瞬间表现完整，画面完成度高。\\\"}]}"
            }]
          }],
          "usage": {"input_tokens": 960, "output_tokens": 120}
        }
        """.utf8)

        let result = try ArkAestheticReviewClient().decodeResponse(data, request: request)

        XCTAssertEqual(result.response.requestID, "ark-request-2")
        XCTAssertEqual(result.response.reviews.map(\.photoID), ["photo_001", "photo_002"])
        XCTAssertEqual(result.response.reviews.map(\.score), [70, 92])
        XCTAssertEqual(result.response.reviews[1].dimensions.moment, 95)
        XCTAssertEqual(
            result.response.reviews[1].summary,
            "主体和瞬间表现完整，画面完成度高。"
        )
        XCTAssertEqual(result.usage.inputTokens, 960)
        XCTAssertEqual(result.usage.outputTokens, 120)
    }

    func testIgnoresLegacyProviderRankFields() throws {
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .burst, groupID: "burst-8"),
            localPhotoIDs: ["/private/a.jpg", "/private/b.jpg"],
            requestID: "ark-request-3"
        )
        let data = Data("""
        {"output":[{"type":"message","content":[{"type":"output_text","text":"{\\\"reviews\\\":[{\\\"photo_id\\\":\\\"photo_001\\\",\\\"rank\\\":1,\\\"score\\\":80,\\\"dimensions\\\":{\\\"moment\\\":80,\\\"composition\\\":80,\\\"subject\\\":80,\\\"lighting\\\":80,\\\"storytelling\\\":80},\\\"reasons\\\":[\\\"构图更稳\\\"],\\\"summary\\\":\\\"整体表现稳定，可用于组内比较。\\\"},{\\\"photo_id\\\":\\\"photo_002\\\",\\\"rank\\\":1,\\\"score\\\":70,\\\"dimensions\\\":{\\\"moment\\\":70,\\\"composition\\\":70,\\\"subject\\\":70,\\\"lighting\\\":70,\\\"storytelling\\\":70},\\\"reasons\\\":[\\\"光线自然\\\"],\\\"summary\\\":\\\"光线自然，其他方面表现普通。\\\"}]}"}]}]}
        """.utf8)

        let result = try ArkAestheticReviewClient().decodeResponse(
            data,
            request: request
        )
        XCTAssertEqual(result.response.reviews.map(\.score), [80, 70])
    }

    func testDecodesValidatedJSONObjectWrappedInProviderText() throws {
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .finalSelection, groupID: "ai-final-007"),
            localPhotoIDs: ["/private/a.jpg", "/private/b.jpg"],
            requestID: "ark-request-wrapped"
        )
        let payload = """
        结果如下：
        {"reviews":[{"photo_id":"photo_001","rank":2,"score":74,"dimensions":{"moment":72,"composition":78,"subject":74,"lighting":75,"storytelling":71},"reasons":["构图完整"],"summary":"构图完整，整体表现可用于组内比较。"},{"photo_id":"photo_002","rank":1,"score":91,"dimensions":{"moment":92,"composition":90,"subject":95,"lighting":88,"storytelling":91},"reasons":["主体突出"],"summary":"主体突出，画面整体表现更完整。"}]}
        请查收。
        """
        let escapedPayload = try String(
            data: JSONEncoder().encode(payload),
            encoding: .utf8
        )!
        let data = Data("""
        {"output":[{"type":"message","content":[{"type":"output_text","text":\(escapedPayload)}]}]}
        """.utf8)

        let result = try ArkAestheticReviewClient().decodeResponse(data, request: request)

        XCTAssertEqual(
            result.response.reviews.max(by: { $0.score < $1.score })?.photoID,
            "photo_002"
        )
    }

    func testDecodesAndValidatesFunctionCallArguments() throws {
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .finalSelection, groupID: "ai-final-tool"),
            localPhotoIDs: ["/private/a.jpg", "/private/b.jpg"],
            requestID: "ark-request-tool"
        )
        let data = Data("""
        {
          "output": [{
            "type": "function_call",
            "name": "submit_photo_reviews",
            "arguments": "{\\\"reviews\\\":[{\\\"photo_id\\\":\\\"photo_001\\\",\\\"rank\\\":2,\\\"score\\\":73,\\\"dimensions\\\":{\\\"moment\\\":70,\\\"composition\\\":74,\\\"subject\\\":72,\\\"lighting\\\":80,\\\"storytelling\\\":69},\\\"reasons\\\":[\\\"光线自然\\\"],\\\"summary\\\":\\\"光线自然，但叙事表现相对普通。\\\"},{\\\"photo_id\\\":\\\"photo_002\\\",\\\"rank\\\":1,\\\"score\\\":94,\\\"dimensions\\\":{\\\"moment\\\":97,\\\"composition\\\":92,\\\"subject\\\":94,\\\"lighting\\\":91,\\\"storytelling\\\":96},\\\"reasons\\\":[\\\"瞬间生动\\\"],\\\"summary\\\":\\\"瞬间和叙事突出，画面完成度高。\\\"}]}"
          }],
          "usage": {"input_tokens": 900, "output_tokens": 100}
        }
        """.utf8)

        let result = try ArkAestheticReviewClient().decodeResponse(data, request: request)

        XCTAssertEqual(
            result.response.reviews.max(by: { $0.score < $1.score })?.photoID,
            "photo_002"
        )
        XCTAssertEqual(result.usage.outputTokens, 100)
    }

    func testReportsSafeResponseFailureStagesWithoutProviderPayload() {
        let request = AestheticReviewRequestBuilder.make(
            scope: AestheticReviewScope(kind: .finalSelection, groupID: "ai-final-stage"),
            localPhotoIDs: ["/private/a.jpg", "/private/b.jpg"],
            requestID: "ark-request-stage"
        )
        let cases: [(Data, ArkAestheticReviewResponseFailureStage)] = [
            (
                Data("{\"usage\":{\"input_tokens\":100}}".utf8),
                .responseEnvelope
            ),
            (
                Data("{\"output\":[{\"type\":\"reasoning\"}]}".utf8),
                .missingReviewPayload
            ),
            (
                Data("{\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"{\\\"reviews\\\":{}}\"}]}]}".utf8),
                .reviewPayloadSchema
            ),
        ]

        for (data, expectedStage) in cases {
            XCTAssertThrowsError(try ArkAestheticReviewClient().decodeResponse(data, request: request)) { error in
                XCTAssertEqual(
                    error as? ArkAestheticReviewClientError,
                    .invalidResponse(stage: expectedStage)
                )
                XCTAssertFalse(error.localizedDescription.contains("reviews"))
                XCTAssertFalse(error.localizedDescription.contains("photo_"))
            }
        }
    }

    func testExtractsOnlySafeProviderErrorCodes() {
        let client = ArkAestheticReviewClient()
        let safePayload = Data("""
        {"error":{"code":"ModelNotFound","message":"must never be shown"}}
        """.utf8)
        let unsafePayload = Data("""
        {"error":{"code":"data:image/jpeg;base64,private-preview"}}
        """.utf8)

        XCTAssertEqual(client.providerErrorCode(from: safePayload), "ModelNotFound")
        XCTAssertNil(client.providerErrorCode(from: unsafePayload))
    }

}
