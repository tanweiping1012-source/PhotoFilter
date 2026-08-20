import Foundation

struct OpenAICompatibleAestheticReviewClient {
    let model: AIModelDescriptor

    func review(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        previewSize: AIReviewPreviewSize = .small,
        apiKey: String,
        session: URLSession = AIReviewURLSession.shared
    ) async throws -> AestheticReviewResult {
        var urlRequest = try makeURLRequest(
            request: request,
            previews: previews,
            previewSize: previewSize,
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
        previewSize: AIReviewPreviewSize = .small,
        apiKey: String
    ) throws -> URLRequest {
        guard model.protocolID == .openAICompatibleChatCompletions,
              model.isReady,
              let profile = model.compatibilityProfile else {
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
        var content: [[String: Any]] = [
            [
                "type": "text",
                "text": AestheticReviewPrompt.userPrompt(for: request),
            ],
        ]
        for input in request.photos {
            guard let preview = previewByID[input.photoID] else {
                throw AestheticReviewClientError.incompletePreviewSet
            }
            var imageURL: [String: Any] = [
                "url": "data:image/jpeg;base64,\(preview.jpegData.base64EncodedString())",
            ]
            if profile == .openAI || profile == .xAI {
                imageURL["detail"] = previewSize == .small ? "low" : "high"
            }
            content.append([
                "type": "image_url",
                "image_url": imageURL,
            ])
        }

        var body: [String: Any] = [
            "model": model.apiModelID,
            "messages": [
                [
                    "role": "system",
                    "content": AestheticReviewPrompt.jsonSystemPrompt,
                ],
                [
                    "role": "user",
                    "content": content,
                ],
            ],
        ]
        if model.supportsJSONResponseFormat {
            body["response_format"] = [
                "type": "json_object",
            ]
        }
        switch profile {
        case .openAI:
            body["max_completion_tokens"] = AestheticReviewPrompt.maximumOutputTokens
            body["reasoning_effort"] = "low"
        case .gemini:
            body["max_completion_tokens"] = AestheticReviewPrompt.maximumOutputTokens
            body["reasoning_effort"] = "low"
        case .qwen:
            body["max_tokens"] = AestheticReviewPrompt.maximumOutputTokens
            body["enable_thinking"] = false
        case .xAI:
            body["max_tokens"] = AestheticReviewPrompt.maximumOutputTokens
            body["reasoning_effort"] = "low"
        case .moonshot:
            body["max_tokens"] = AestheticReviewPrompt.maximumOutputTokens
        case .zhipu:
            body["max_tokens"] = AestheticReviewPrompt.maximumOutputTokens
            body["thinking"] = ["type": "disabled"]
        case .hunyuan, .custom:
            body["max_tokens"] = AestheticReviewPrompt.maximumOutputTokens
        }

        var urlRequest = URLRequest(url: model.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
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
        let completion: OpenAICompatibleChatResponse
        do {
            completion = try JSONDecoder().decode(
                OpenAICompatibleChatResponse.self,
                from: data
            )
        } catch {
            throw AestheticReviewClientError.invalidResponse(
                stage: .responseEnvelope
            )
        }
        guard let content = completion.choices.first?.message.content,
              let payloadData = normalizedJSONData(from: content) else {
            throw AestheticReviewClientError.invalidResponse(
                stage: .missingReviewPayload
            )
        }
        let payload: OpenAICompatibleReviewPayload
        do {
            payload = try JSONDecoder().decode(
                OpenAICompatibleReviewPayload.self,
                from: payloadData
            )
        } catch {
            throw AestheticReviewClientError.invalidResponse(
                stage: .reviewPayloadSchema
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
                inputTokens: completion.usage?.promptTokens,
                outputTokens: completion.usage?.completionTokens
            )
        )
    }

    func providerErrorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return SafeProviderErrorCode.find(in: object)
    }

    private func normalizedJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3,
                  lines.last?.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ) == "```" else {
                return nil
            }
            unfenced = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            unfenced = trimmed
        }
        if let data = unfenced.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }
        guard let firstBrace = unfenced.firstIndex(of: "{"),
              let lastBrace = unfenced.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        return String(unfenced[firstBrace...lastBrace]).data(using: .utf8)
    }
}

enum SafeProviderErrorCode {
    static func find(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let normalizedKey = key
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "")
                guard [
                    "code",
                    "errorcode",
                    "statuscode",
                    "type",
                ].contains(normalizedKey) else {
                    continue
                }
                let candidate: String?
                if let string = value as? String {
                    candidate = string
                } else if let number = value as? NSNumber {
                    candidate = number.stringValue
                } else {
                    candidate = nil
                }
                if let candidate, isSafe(candidate) {
                    return candidate
                }
            }
            for value in dictionary.values {
                if let code = find(in: value) {
                    return code
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let code = find(in: value) {
                    return code
                }
            }
        }
        return nil
    }

    private static func isSafe(_ value: String) -> Bool {
        guard (1...80).contains(value.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }
}

private struct OpenAICompatibleChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct OpenAICompatibleReviewPayload: Decodable {
    let reviews: [AestheticReviewEntry]
}
