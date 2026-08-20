import Foundation

struct AnthropicAestheticReviewClient {
    let model: AIModelDescriptor

    func review(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        apiKey: String,
        session: URLSession = AIReviewURLSession.shared
    ) async throws -> AestheticReviewResult {
        var urlRequest = try makeURLRequest(
            request: request,
            previews: previews,
            apiKey: apiKey
        )
        urlRequest.timeoutInterval = 90

        let (data, urlResponse) = try await session.data(for: urlRequest)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw AestheticReviewClientError.invalidResponse(
                stage: .transportEnvelope
            )
        }
        guard (200...299).contains(response.statusCode) else {
            throw AestheticReviewClientError.requestRejected(
                statusCode: response.statusCode,
                providerCode: providerErrorCode(from: data),
                retryAfter: AestheticReviewClientError.retryAfter(from: response)
            )
        }
        return try decodeResponse(data, request: request)
    }

    func makeURLRequest(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        apiKey: String
    ) throws -> URLRequest {
        guard model.protocolID == .anthropicMessages, model.isReady else {
            throw AestheticReviewClientError.invalidConfiguration
        }
        let expectedIDs = request.photos.map(\.photoID)
        let previewIDs = previews.map(\.opaquePhotoID)
        guard previews.count == expectedIDs.count,
              Set(previewIDs).count == previewIDs.count,
              Set(previewIDs) == Set(expectedIDs) else {
            throw AestheticReviewClientError.incompletePreviewSet
        }

        let previewByID = Dictionary(
            uniqueKeysWithValues: previews.map {
                ($0.opaquePhotoID, $0)
            }
        )
        var content: [[String: Any]] = []
        for input in request.photos {
            guard let preview = previewByID[input.photoID] else {
                throw AestheticReviewClientError.incompletePreviewSet
            }
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": preview.jpegData.base64EncodedString(),
                ],
            ])
        }
        content.append([
            "type": "text",
            "text": AestheticReviewPrompt.userPrompt(for: request),
        ])

        let toolName = "submit_photo_reviews"
        let body: [String: Any] = [
            "model": model.apiModelID,
            "max_tokens": AestheticReviewPrompt.maximumOutputTokens,
            "system": AestheticReviewPrompt.systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": content,
                ],
            ],
            "tools": [
                [
                    "name": toolName,
                    "description": "提交每张照片基于统一绝对标尺的独立评分。",
                    "input_schema": reviewSchema(for: request),
                    "strict": true,
                ],
            ],
            "tool_choice": [
                "type": "tool",
                "name": toolName,
            ],
        ]

        var urlRequest = URLRequest(url: model.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(
            "2023-06-01",
            forHTTPHeaderField: "anthropic-version"
        )
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = try JSONSerialization.data(
            withJSONObject: body
        )
        return urlRequest
    }

    func decodeResponse(
        _ data: Data,
        request: AestheticReviewRequest
    ) throws -> AestheticReviewResult {
        let message: AnthropicMessageResponse
        do {
            message = try JSONDecoder().decode(
                AnthropicMessageResponse.self,
                from: data
            )
        } catch {
            throw AestheticReviewClientError.invalidResponse(
                stage: .responseEnvelope
            )
        }
        guard let payload = message.content.first(where: {
            $0.type == "tool_use"
                && $0.name == "submit_photo_reviews"
        })?.input else {
            throw AestheticReviewClientError.invalidResponse(
                stage: .missingReviewPayload
            )
        }
        let response = AestheticReviewResponse(
            version: AestheticReviewContract.version,
            requestID: request.requestID,
            scope: request.scope,
            reviews: payload.reviews
        )
        try AestheticReviewValidator.validate(response, for: request)
        return AestheticReviewResult(
            response: response,
            usage: AestheticReviewUsage(
                inputTokens: message.usage?.inputTokens,
                outputTokens: message.usage?.outputTokens
            )
        )
    }

    func providerErrorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return SafeProviderErrorCode.find(in: object)
    }

    private func reviewSchema(
        for request: AestheticReviewRequest
    ) -> [String: Any] {
        [
            "type": "object",
            "properties": [
                "reviews": [
                    "type": "array",
                    "minItems": request.photos.count,
                    "maxItems": request.photos.count,
                    "items": [
                        "type": "object",
                        "properties": [
                            "photo_id": [
                                "type": "string",
                                "enum": request.photos.map(\.photoID),
                            ],
                            "score": [
                                "type": "integer",
                                "minimum": 0,
                                "maximum": 100,
                            ],
                            "dimensions": scoreDimensionsSchema,
                            "reasons": [
                                "type": "array",
                                "minItems": 1,
                                "maxItems": 3,
                                "items": [
                                    "type": "string",
                                    "minLength": 2,
                                    "maxLength": 80,
                                ],
                            ],
                            "summary": [
                                "type": "string",
                                "minLength": 4,
                                "maxLength": 120,
                            ],
                        ],
                        "required": [
                            "photo_id",
                            "score",
                            "dimensions",
                            "reasons",
                            "summary",
                        ],
                        "additionalProperties": false,
                    ],
                ],
            ],
            "required": ["reviews"],
            "additionalProperties": false,
        ]
    }

    private var scoreDimensionsSchema: [String: Any] {
        let score: [String: Any] = [
            "type": "integer",
            "minimum": 0,
            "maximum": 100,
        ]
        return [
            "type": "object",
            "properties": [
                "moment": score,
                "composition": score,
                "subject": score,
                "lighting": score,
                "storytelling": score,
            ],
            "required": [
                "moment",
                "composition",
                "subject",
                "lighting",
                "storytelling",
            ],
            "additionalProperties": false,
        ]
    }
}

private struct AnthropicMessageResponse: Decodable {
    let content: [ContentBlock]
    let usage: Usage?

    struct ContentBlock: Decodable {
        let type: String
        let name: String?
        let input: AnthropicReviewPayload?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct AnthropicReviewPayload: Decodable {
    let reviews: [AestheticReviewEntry]
}
