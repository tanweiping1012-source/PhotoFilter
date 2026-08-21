import Foundation
import XCTest

@testable import PhotoCurator

final class MiniMaxAestheticReviewClientTests: XCTestCase {
    private let request = AestheticReviewRequest(
        requestID: "request-minimax",
        scope: AestheticReviewScope(
            kind: .similarity,
            groupID: "group-minimax"
        ),
        photos: [
            AestheticReviewInput(photoID: "photo_001", position: 1),
            AestheticReviewInput(photoID: "photo_002", position: 2),
        ]
    )

    private let previews = [
        AestheticReviewPreview(
            opaquePhotoID: "photo_001",
            jpegData: Data([0x01, 0x02])
        ),
        AestheticReviewPreview(
            opaquePhotoID: "photo_002",
            jpegData: Data([0x03, 0x04])
        ),
    ]

    func testRequestUsesMiniMaxM3AndOnlyAnonymousDataURLs() throws {
        let urlRequest = try MiniMaxAestheticReviewClient().makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "minimax-secret-key"
        )
        let body = try XCTUnwrap(urlRequest.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.minimaxi.com/v1/chat/completions"
        )
        XCTAssertEqual(
            urlRequest.value(forHTTPHeaderField: "Authorization"),
            "Bearer minimax-secret-key"
        )
        XCTAssertEqual(object["model"] as? String, "MiniMax-M3")
        XCTAssertEqual(
            (object["thinking"] as? [String: Any])?["type"] as? String,
            "disabled"
        )
        XCTAssertEqual(object["reasoning_split"] as? Bool, true)
        let imageURLs = try imageURLPayloads(from: object)
        XCTAssertEqual(imageURLs.map { $0["detail"] as? String }, ["low", "low"])
        XCTAssertEqual(
            imageURLs.map { $0["max_long_side_pixel"] as? Int },
            [512, 512]
        )
        XCTAssertTrue(bodyText.contains("AQI="))
        XCTAssertTrue(bodyText.contains("AwQ="))
        XCTAssertTrue(bodyText.contains("data:image"))
        XCTAssertTrue(bodyText.contains("photo_001"))
        XCTAssertTrue(bodyText.contains("photo_002"))
        XCTAssertTrue(bodyText.contains("\"dimensions\""))
        XCTAssertTrue(bodyText.contains("\"summary\""))
        XCTAssertFalse(bodyText.contains("minimax-secret-key"))
        XCTAssertFalse(bodyText.contains("/Users/"))
        XCTAssertFalse(bodyText.contains(".jpg"))
    }

    func testLargePreviewUsesHighDetailAnd1536PixelBoundary() throws {
        let urlRequest = try MiniMaxAestheticReviewClient().makeURLRequest(
            request: request,
            previews: previews,
            previewSize: .large,
            apiKey: "minimax-secret-key"
        )
        let body = try XCTUnwrap(urlRequest.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let imageURLs = try imageURLPayloads(from: object)

        XCTAssertEqual(imageURLs.map { $0["detail"] as? String }, ["high", "high"])
        XCTAssertEqual(
            imageURLs.map { $0["max_long_side_pixel"] as? Int },
            [1_536, 1_536]
        )
    }

    func testDecodesToolCallAndValidatesCompleteIndependentScores() throws {
        let data = try responseData(
            toolArguments: """
            {"reviews":[{"photo_id":"photo_001","rank":1,"score":92,"dimensions":{"moment":93,"composition":90,"subject":95,"lighting":92,"storytelling":91},"reasons":["主体明确且光线自然"],"summary":"主体和光线表现完整，画面完成度高。"},{"photo_id":"photo_002","rank":2,"score":81,"dimensions":{"moment":79,"composition":86,"subject":82,"lighting":83,"storytelling":76},"reasons":["构图稳定但叙事稍弱"],"summary":"构图稳定，但瞬间和叙事表现稍弱。"}]}
            """,
            content: nil
        )

        let result = try MiniMaxAestheticReviewClient().decodeResponse(
            data,
            request: request
        )

        XCTAssertEqual(result.response.requestID, request.requestID)
        XCTAssertEqual(result.response.scope, request.scope)
        XCTAssertEqual(result.response.reviews.map { $0.total(with: .balanced) }, [92, 81])
        XCTAssertEqual(result.response.reviews.first?.dimensions.subject, 95)
        XCTAssertEqual(result.usage.inputTokens, 1200)
        XCTAssertEqual(result.usage.outputTokens, 120)
    }

    func testDecodesFencedJSONObjectWhenToolCallIsAbsent() throws {
        let data = try responseData(
            toolArguments: nil,
            content: """
            ```json
            {"reviews":[{"photo_id":"photo_001","rank":1,"score":90,"dimensions":{"moment":91,"composition":89,"subject":94,"lighting":87,"storytelling":90},"reasons":["主体突出且层次完整"],"summary":"主体和层次清楚，整体表现更加完整。"},{"photo_id":"photo_002","rank":2,"score":78,"dimensions":{"moment":77,"composition":80,"subject":76,"lighting":81,"storytelling":74},"reasons":["画面可用但重点较弱"],"summary":"画面技术可用，但主体重点不够明确。"}]}
            ```
            """
        )

        let result = try MiniMaxAestheticReviewClient().decodeResponse(
            data,
            request: request
        )

        XCTAssertEqual(result.response.reviews.count, 2)
        XCTAssertEqual(result.response.reviews.first?.photoID, "photo_001")
    }

    func testRejectsProviderStatusAndIgnoresLegacyRankFields() throws {
        let providerFailure = try responseData(
            toolArguments: nil,
            content: nil,
            baseStatusCode: 1002
        )
        XCTAssertThrowsError(
            try MiniMaxAestheticReviewClient().decodeResponse(
                providerFailure,
                request: request
            )
        ) { error in
            XCTAssertEqual(
                error as? AestheticReviewClientError,
                .requestRejected(
                    statusCode: 200,
                    providerCode: "MiniMax-1002",
                    retryAfter: nil
                )
            )
        }

        let legacyRanking = try responseData(
            toolArguments: """
            {"reviews":[{"photo_id":"photo_001","rank":1,"score":92,"dimensions":{"moment":93,"composition":90,"subject":95,"lighting":92,"storytelling":91},"reasons":["主体明确且光线自然"],"summary":"主体和光线表现完整，画面完成度高。"},{"photo_id":"photo_002","rank":1,"score":81,"dimensions":{"moment":79,"composition":86,"subject":82,"lighting":83,"storytelling":76},"reasons":["构图稳定但叙事稍弱"],"summary":"构图稳定，但瞬间和叙事表现稍弱。"}]}
            """,
            content: nil
        )
        let result = try MiniMaxAestheticReviewClient().decodeResponse(
            legacyRanking,
            request: request
        )
        XCTAssertEqual(result.response.reviews.map { $0.total(with: .balanced) }, [92, 81])
    }

    func testExtractsOnlySafeMiniMaxErrorCode() throws {
        let client = MiniMaxAestheticReviewClient()
        let safe = try JSONSerialization.data(withJSONObject: [
            "base_resp": ["status_code": 1004, "status_msg": "secret body"],
        ])
        let unsafe = try JSONSerialization.data(withJSONObject: [
            "error": ["code": "bad code with spaces"],
        ])

        XCTAssertEqual(client.providerErrorCode(from: safe), "1004")
        XCTAssertNil(client.providerErrorCode(from: unsafe))
    }

    func testObservedRateLimitShapeClassifiesTokenPlanFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiniMaxRateLimitURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await MiniMaxAestheticReviewClient().review(
                request: request,
                previews: previews,
                apiKey: "sk-cp-diagnostic-key",
                session: session
            )
            XCTFail("Expected the observed HTTP 429 response to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? AestheticReviewClientError,
                .requestRejected(
                    statusCode: 429,
                    providerCode: "MiniMax-TokenPlan-RateLimit",
                    retryAfter: nil
                )
            )
            XCTAssertTrue(error.localizedDescription.contains("Token Plan"))
            XCTAssertTrue(error.localizedDescription.contains("5 小时"))
            XCTAssertFalse(error.localizedDescription.contains("rate_limit"))
        }

        try await Task.sleep(for: .milliseconds(250))
    }

    func testOrdinaryKeyUsesGenericMiniMaxRateLimitCategory() {
        let code = MiniMaxAestheticReviewClient().providerFailureCode(
            statusCode: 429,
            data: Data("{}".utf8),
            apiKey: "ordinary-minimax-key"
        )

        XCTAssertEqual(code, "MiniMax-RateLimit")
    }

    private func responseData(
        toolArguments: String?,
        content: String?,
        baseStatusCode: Int = 0
    ) throws -> Data {
        var message: [String: Any] = [
            "role": "assistant",
            "content": content ?? NSNull(),
        ]
        if let toolArguments {
            message["tool_calls"] = [[
                "id": "call-review",
                "type": "function",
                "function": [
                    "name": "submit_photo_reviews",
                    "arguments": toolArguments,
                ],
            ]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "id": "completion-minimax",
            "choices": [[
                "index": 0,
                "message": message,
                "finish_reason": "stop",
            ]],
            "model": "MiniMax-M3",
            "usage": [
                "prompt_tokens": 1200,
                "completion_tokens": 120,
                "total_tokens": 1320,
            ],
            "base_resp": [
                "status_code": baseStatusCode,
                "status_msg": baseStatusCode == 0 ? "success" : "failed",
            ],
        ])
    }

    private func imageURLPayloads(
        from body: [String: Any]
    ) throws -> [[String: Any]] {
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(
            messages.first(where: { $0["role"] as? String == "user" })
        )
        let content = try XCTUnwrap(userMessage["content"] as? [[String: Any]])
        return content.compactMap { part in
            guard part["type"] as? String == "image_url" else { return nil }
            return part["image_url"] as? [String: Any]
        }
    }
}

private final class MiniMaxRateLimitURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = Data(
            """
            {
              "type": "error",
              "error": {
                "type": "rate_limit_error",
                "message": "rate_limit",
                "http_code": 429
              },
              "request_id": "redacted"
            }
            """.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
