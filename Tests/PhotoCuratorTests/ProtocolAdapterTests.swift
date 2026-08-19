import Foundation
import XCTest

@testable import PhotoCurator

final class ProtocolAdapterTests: XCTestCase {
    private let request = AestheticReviewRequest(
        requestID: "request-protocol",
        scope: AestheticReviewScope(
            kind: .similarity,
            groupID: "group-protocol"
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

    func testOpenAICompatibleBuiltInsShareOneRequestEnvelope() throws {
        let expectations: [
            (
                id: AIModelID,
                endpoint: String,
                apiModelID: String,
                maxTokenKey: String
            )
        ] = [
            (
                .openAIGPT54Mini,
                "https://api.openai.com/v1/chat/completions",
                "gpt-5.4-mini",
                "max_completion_tokens"
            ),
            (
                .googleGemini37Flash,
                "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                "gemini-3.7-flash",
                "max_completion_tokens"
            ),
            (
                .alibabaQwen38Max,
                "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                "qwen3.8-max",
                "max_tokens"
            ),
            (
                .xAIGrok46,
                "https://api.x.ai/v1/chat/completions",
                "grok-4.6",
                "max_tokens"
            ),
        ]

        for expectation in expectations {
            let model = AIModelCatalog.model(for: expectation.id)
            let urlRequest = try OpenAICompatibleAestheticReviewClient(
                model: model
            ).makeURLRequest(
                request: request,
                previews: previews,
                previewSize: .medium,
                apiKey: "provider-secret-key"
            )
            let body = try XCTUnwrap(urlRequest.httpBody)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body)
                    as? [String: Any]
            )
            let bodyText = try XCTUnwrap(
                String(data: body, encoding: .utf8)
            )

            XCTAssertEqual(
                urlRequest.url?.absoluteString,
                expectation.endpoint
            )
            XCTAssertEqual(
                urlRequest.value(
                    forHTTPHeaderField: "Authorization"
                ),
                "Bearer provider-secret-key"
            )
            XCTAssertEqual(
                object["model"] as? String,
                expectation.apiModelID
            )
            XCTAssertEqual(
                (object["response_format"] as? [String: Any])?["type"]
                    as? String,
                "json_object"
            )
            XCTAssertEqual(
                object[expectation.maxTokenKey] as? Int,
                1_600
            )
            XCTAssertEqual(
                try imageURLPayloads(from: object).count,
                2
            )
            XCTAssertTrue(bodyText.contains("AQI="))
            XCTAssertTrue(bodyText.contains("AwQ="))
            XCTAssertFalse(bodyText.contains("provider-secret-key"))
            XCTAssertFalse(bodyText.contains("/Users/"))
        }
    }

    func testEveryOpenAICompatibleCatalogModelBuildsImageRequest()
        throws {
        let models = AIModelCatalog.availableModels.filter {
            $0.protocolID == .openAICompatibleChatCompletions
                && $0.id != .customOpenAICompatible
                && $0.isReady
        }
        XCTAssertFalse(models.isEmpty)

        for model in models {
            let urlRequest = try OpenAICompatibleAestheticReviewClient(
                model: model
            ).makeURLRequest(
                request: request,
                previews: previews,
                previewSize: .small,
                apiKey: "provider-secret-key"
            )
            let body = try XCTUnwrap(urlRequest.httpBody)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body)
                    as? [String: Any]
            )

            XCTAssertEqual(urlRequest.url, model.endpoint)
            XCTAssertEqual(object["model"] as? String, model.apiModelID)
            XCTAssertEqual(try imageURLPayloads(from: object).count, 2)
            XCTAssertEqual(
                object["response_format"] != nil,
                model.supportsJSONResponseFormat
            )
        }
    }

    func testArkAndMiniMaxUseSelectedCatalogModelID() throws {
        let arkModel = AIModelCatalog.model(for: .doubaoSeed21Pro)
        let arkRequest = try ArkAestheticReviewClient(
            model: arkModel
        ).makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "ark-secret-key"
        )
        let arkBody = try XCTUnwrap(arkRequest.httpBody)
        XCTAssertTrue(
            String(decoding: arkBody, as: UTF8.self)
                .contains(arkModel.apiModelID)
        )

        let miniMaxModel = AIModelCatalog.model(for: .miniMaxM3)
        let miniMaxRequest = try MiniMaxAestheticReviewClient(
            model: miniMaxModel
        ).makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "minimax-secret-key"
        )
        let miniMaxBody = try XCTUnwrap(miniMaxRequest.httpBody)
        XCTAssertTrue(
            String(decoding: miniMaxBody, as: UTF8.self)
                .contains(miniMaxModel.apiModelID)
        )
    }

    func testQwenProfileDisablesThinking() throws {
        let body = try requestBody(
            for: AIModelCatalog.model(for: .alibabaQwen38Max)
        )
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        XCTAssertNil(body["reasoning_effort"])
    }

    func testOpenAIAndGeminiProfilesUseLowReasoning() throws {
        for modelID in [
            AIModelID.openAIGPT54Mini,
            .googleGemini37Flash,
        ] {
            let body = try requestBody(
                for: AIModelCatalog.model(for: modelID)
            )
            XCTAssertEqual(body["reasoning_effort"] as? String, "low")
        }
    }

    func testCustomCompatibleModelUsesValidatedEndpointAndEnvelope()
        throws {
        let configuration = CustomOpenAICompatibleConfiguration(
            displayName: "Gateway Vision",
            endpointString: "https://gateway.example.com/v1/chat/completions",
            apiModelID: "vision-latest"
        )
        let model = AIModelCatalog.model(
            for: .customOpenAICompatible,
            customConfiguration: configuration
        )
        let urlRequest = try OpenAICompatibleAestheticReviewClient(
            model: model
        ).makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "custom-secret-key"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(urlRequest.httpBody)
            ) as? [String: Any]
        )

        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            configuration.endpointString
        )
        XCTAssertEqual(object["model"] as? String, "vision-latest")
        XCTAssertEqual(object["max_tokens"] as? Int, 1_600)
    }

    func testOpenAICompatibleResponseUsesUnifiedValidator() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "message": [
                    "content": """
                    {"reviews":[{"photo_id":"photo_001","rank":1,"score":92,"dimensions":{"moment":94,"composition":90,"subject":95,"lighting":91,"storytelling":92},"reasons":["主体明确"],"summary":"主体和瞬间表现完整，画面完成度高。"},{"photo_id":"photo_002","rank":2,"score":80,"dimensions":{"moment":78,"composition":84,"subject":81,"lighting":82,"storytelling":75},"reasons":["叙事稍弱"],"summary":"构图稳定，但叙事表现相对较弱。"}]}
                    """,
                ],
            ]],
            "usage": [
                "prompt_tokens": 800,
                "completion_tokens": 90,
            ],
        ])
        let result = try OpenAICompatibleAestheticReviewClient(
            model: AIModelCatalog.model(for: .openAIGPT54Mini)
        ).decodeResponse(data, request: request)

        XCTAssertEqual(result.response.reviews.map(\.score), [92, 80])
        XCTAssertEqual(result.response.reviews.first?.dimensions.moment, 94)
        XCTAssertEqual(result.usage.inputTokens, 800)
        XCTAssertEqual(result.usage.outputTokens, 90)
    }

    func testAnthropicMessagesUsesBase64ImagesAndForcedTool()
        throws {
        let model = AIModelCatalog.model(
            for: .anthropicClaudeSonnet5
        )
        let urlRequest = try AnthropicAestheticReviewClient(
            model: model
        ).makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "anthropic-secret-key"
        )
        let body = try XCTUnwrap(urlRequest.httpBody)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body)
                as? [String: Any]
        )
        let bodyText = try XCTUnwrap(
            String(data: body, encoding: .utf8)
        )

        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            urlRequest.value(forHTTPHeaderField: "x-api-key"),
            "anthropic-secret-key"
        )
        XCTAssertEqual(
            urlRequest.value(
                forHTTPHeaderField: "anthropic-version"
            ),
            "2023-06-01"
        )
        XCTAssertEqual(object["model"] as? String, "claude-sonnet-5")
        XCTAssertEqual(
            (object["tool_choice"] as? [String: Any])?["name"]
                as? String,
            "submit_photo_reviews"
        )
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        let inputSchema = try XCTUnwrap(
            tools.first?["input_schema"] as? [String: Any]
        )
        let schemaText = try XCTUnwrap(
            String(
                data: try JSONSerialization.data(
                    withJSONObject: inputSchema
                ),
                encoding: .utf8
            )
        )
        XCTAssertTrue(schemaText.contains("\"dimensions\""))
        XCTAssertTrue(schemaText.contains("\"summary\""))
        XCTAssertTrue(bodyText.contains("AQI="))
        XCTAssertTrue(bodyText.contains("AwQ="))
        XCTAssertFalse(bodyText.contains("anthropic-secret-key"))
    }

    func testAnthropicResponseUsesUnifiedValidator() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "content": [[
                "type": "tool_use",
                "name": "submit_photo_reviews",
                "input": [
                    "reviews": [
                        [
                            "photo_id": "photo_001",
                            "rank": 1,
                            "score": 94,
                            "dimensions": [
                                "moment": 97,
                                "composition": 92,
                                "subject": 95,
                                "lighting": 91,
                                "storytelling": 94,
                            ],
                            "reasons": ["瞬间自然生动"],
                            "summary": "瞬间和主体表现完整，画面完成度高。",
                        ],
                        [
                            "photo_id": "photo_002",
                            "rank": 2,
                            "score": 79,
                            "dimensions": [
                                "moment": 77,
                                "composition": 83,
                                "subject": 80,
                                "lighting": 81,
                                "storytelling": 74,
                            ],
                            "reasons": ["主体稍弱"],
                            "summary": "构图稳定，但主体和叙事表现稍弱。",
                        ],
                    ],
                ],
            ]],
            "usage": [
                "input_tokens": 900,
                "output_tokens": 100,
            ],
        ])
        let result = try AnthropicAestheticReviewClient(
            model: AIModelCatalog.model(
                for: .anthropicClaudeSonnet5
            )
        ).decodeResponse(data, request: request)

        XCTAssertEqual(result.response.reviews.map(\.score), [94, 79])
        XCTAssertEqual(result.usage.inputTokens, 900)
        XCTAssertEqual(result.usage.outputTokens, 100)
    }

    func testSafeErrorCodeNeverReturnsProviderMessage() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "error": [
                "type": "rate_limit_error",
                "message": "private provider response body",
            ],
        ])
        let client = OpenAICompatibleAestheticReviewClient(
            model: AIModelCatalog.model(for: .xAIGrok46)
        )

        XCTAssertEqual(
            client.providerErrorCode(from: data),
            "rate_limit_error"
        )
        XCTAssertFalse(
            client.providerErrorCode(from: data)?
                .contains("private") ?? true
        )
    }

    private func requestBody(
        for model: AIModelDescriptor
    ) throws -> [String: Any] {
        let urlRequest = try OpenAICompatibleAestheticReviewClient(
            model: model
        ).makeURLRequest(
            request: request,
            previews: previews,
            apiKey: "test-secret-key"
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try XCTUnwrap(urlRequest.httpBody)
            ) as? [String: Any]
        )
    }

    private func imageURLPayloads(
        from body: [String: Any]
    ) throws -> [[String: Any]] {
        let messages = try XCTUnwrap(
            body["messages"] as? [[String: Any]]
        )
        let userMessage = try XCTUnwrap(
            messages.first {
                $0["role"] as? String == "user"
            }
        )
        let content = try XCTUnwrap(
            userMessage["content"] as? [[String: Any]]
        )
        return content.compactMap {
            guard $0["type"] as? String == "image_url" else {
                return nil
            }
            return $0["image_url"] as? [String: Any]
        }
    }
}
