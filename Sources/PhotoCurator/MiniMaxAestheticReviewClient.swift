import Foundation

struct AestheticReviewClient {
    let model: AIModelDescriptor

    init(modelID: AIModelID) {
        model = AIModelCatalog.model(for: modelID)
    }

    init(model: AIModelDescriptor) {
        self.model = model
    }

    func review(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        previewSize: AIReviewPreviewSize = .small,
        apiKey: String,
        session: URLSession = AIReviewURLSession.shared
    ) async throws -> AestheticReviewResult {
        switch model.protocolID {
        case .arkResponses:
            return try await ArkAestheticReviewClient(
                model: model
            ).review(
                request: request,
                previews: previews,
                apiKey: apiKey,
                session: session
            )
        case .miniMaxChatCompletions:
            return try await MiniMaxAestheticReviewClient(
                model: model
            ).review(
                request: request,
                previews: previews,
                previewSize: previewSize,
                apiKey: apiKey,
                session: session
            )
        case .openAICompatibleChatCompletions:
            return try await OpenAICompatibleAestheticReviewClient(
                model: model
            ).review(
                request: request,
                previews: previews,
                previewSize: previewSize,
                apiKey: apiKey,
                session: session
            )
        case .anthropicMessages:
            return try await AnthropicAestheticReviewClient(
                model: model
            ).review(
                request: request,
                previews: previews,
                apiKey: apiKey,
                session: session
            )
        }
    }
}

struct MiniMaxAestheticReviewClient {
    private let model: AIModelDescriptor

    init(
        model: AIModelDescriptor = AIModelCatalog.model(
            for: .miniMaxM3
        )
    ) {
        self.model = model
    }

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
            throw AestheticReviewClientError.invalidResponse(stage: .transportEnvelope)
        }
        guard (200...299).contains(response.statusCode) else {
            throw AestheticReviewClientError.requestRejected(
                statusCode: response.statusCode,
                providerCode: providerFailureCode(
                    statusCode: response.statusCode,
                    data: data,
                    apiKey: apiKey
                ),
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
        let expectedIDs = request.photos.map(\.photoID)
        let previewIDs = previews.map(\.opaquePhotoID)
        guard previews.count == expectedIDs.count,
              Set(previewIDs).count == previewIDs.count,
              Set(previewIDs) == Set(expectedIDs) else {
            throw AestheticReviewClientError.incompletePreviewSet
        }

        let previewByID = Dictionary(
            uniqueKeysWithValues: previews.map { ($0.opaquePhotoID, $0) }
        )
        let content: [MiniMaxMessageContentPart] = [
            .text(AestheticReviewPrompt.userPrompt(for: request)),
        ] + request.photos.compactMap { input in
            guard let preview = previewByID[input.photoID] else { return nil }
            return .imageURL(
                url: "data:image/jpeg;base64,\(preview.jpegData.base64EncodedString())",
                detail: previewSize.miniMaxDetail,
                maximumPixelSize: previewSize.maximumPixelSize
            )
        }
        let body = MiniMaxChatRequestBody(
            model: model.apiModelID,
            messages: [
                MiniMaxChatMessage(
                    role: "system",
                    content: .text(AestheticReviewPrompt.systemPrompt)
                ),
                MiniMaxChatMessage(role: "user", content: .parts(content)),
            ],
            tools: [MiniMaxReviewTool(request: request)],
            temperature: 0.1,
            maxCompletionTokens: AestheticReviewPrompt.maximumOutputTokens,
            thinking: MiniMaxThinking(type: "disabled"),
            reasoningSplit: true
        )

        var urlRequest = URLRequest(url: model.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    func decodeResponse(
        _ data: Data,
        request: AestheticReviewRequest
    ) throws -> AestheticReviewResult {
        let completion: MiniMaxChatResponse
        do {
            completion = try JSONDecoder().decode(MiniMaxChatResponse.self, from: data)
        } catch {
            throw AestheticReviewClientError.invalidResponse(stage: .responseEnvelope)
        }
        if let statusCode = completion.baseResponse?.statusCode, statusCode != 0 {
            throw AestheticReviewClientError.requestRejected(
                statusCode: 200,
                providerCode: "MiniMax-\(statusCode)",
                retryAfter: nil
            )
        }

        let message = completion.choices.first?.message
        let functionArguments = message?.toolCalls?
            .first(where: { $0.function.name == MiniMaxReviewTool.name })?
            .function.arguments
        let outputText = message?.content ?? ""
        guard let payloadData = functionArguments.flatMap(normalizedJSONData)
            ?? (outputText.isEmpty ? nil : normalizedJSONData(from: outputText)) else {
            throw AestheticReviewClientError.invalidResponse(stage: .missingReviewPayload)
        }

        let payload: MiniMaxReviewPayload
        do {
            payload = try JSONDecoder().decode(MiniMaxReviewPayload.self, from: payloadData)
        } catch {
            throw AestheticReviewClientError.invalidResponse(stage: .reviewPayloadSchema)
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
        return findSafeErrorCode(in: object)
    }

    func providerFailureCode(
        statusCode: Int,
        data: Data,
        apiKey: String
    ) -> String? {
        if let code = providerErrorCode(from: data) {
            return code
        }
        guard statusCode == 429 else {
            return nil
        }
        return apiKey.hasPrefix("sk-cp")
            ? "MiniMax-TokenPlan-RateLimit"
            : "MiniMax-RateLimit"
    }

    private func normalizedJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3,
                  lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
                return nil
            }
            unfenced = lines.dropFirst().dropLast().joined(separator: "\n")
        } else {
            unfenced = trimmed
        }

        if let directData = unfenced.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: directData)) != nil {
            return directData
        }
        guard let firstBrace = unfenced.firstIndex(of: "{"),
              let lastBrace = unfenced.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        return String(unfenced[firstBrace...lastBrace]).data(using: .utf8)
    }

    private func findSafeErrorCode(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let normalizedKey = key
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "")
                guard ["code", "errorcode", "statuscode"].contains(normalizedKey) else {
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
                if let candidate, isSafeErrorCode(candidate) {
                    return candidate
                }
            }
            for value in dictionary.values {
                if let code = findSafeErrorCode(in: value) {
                    return code
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let code = findSafeErrorCode(in: value) {
                    return code
                }
            }
        }
        return nil
    }

    private func isSafeErrorCode(_ value: String) -> Bool {
        guard (1...80).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }
}

private struct MiniMaxChatRequestBody: Encodable {
    let model: String
    let messages: [MiniMaxChatMessage]
    let tools: [MiniMaxReviewTool]
    let temperature: Double
    let maxCompletionTokens: Int
    let thinking: MiniMaxThinking
    let reasoningSplit: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, thinking
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningSplit = "reasoning_split"
    }
}

private struct MiniMaxThinking: Encodable {
    let type: String
}

private struct MiniMaxChatMessage: Encodable {
    let role: String
    let content: MiniMaxMessageContent
}

private enum MiniMaxMessageContent: Encodable {
    case text(String)
    case parts([MiniMaxMessageContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .parts(parts):
            try container.encode(parts)
        }
    }
}

private enum MiniMaxMessageContentPart: Encodable {
    case text(String)
    case imageURL(url: String, detail: String, maximumPixelSize: Int)

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }

    enum ImageCodingKeys: String, CodingKey {
        case url, detail
        case maximumPixelSize = "max_long_side_pixel"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url, detail, maximumPixelSize):
            try container.encode("image_url", forKey: .type)
            var image = container.nestedContainer(
                keyedBy: ImageCodingKeys.self,
                forKey: .imageURL
            )
            try image.encode(url, forKey: .url)
            try image.encode(detail, forKey: .detail)
            try image.encode(maximumPixelSize, forKey: .maximumPixelSize)
        }
    }
}

private struct MiniMaxReviewTool: Encodable {
    static let name = "submit_photo_reviews"

    let type = "function"
    let function: Function

    init(request: AestheticReviewRequest) {
        function = Function(request: request)
    }

    struct Function: Encodable {
        let name = MiniMaxReviewTool.name
        let description = "提交每张照片基于统一绝对标尺的独立评分。"
        let parameters: Parameters
        let strict = true

        init(request: AestheticReviewRequest) {
            parameters = Parameters(request: request)
        }
    }

    struct Parameters: Encodable {
        let type = "object"
        let properties: Properties
        let required = ["reviews"]
        let additionalProperties = false

        init(request: AestheticReviewRequest) {
            properties = Properties(request: request)
        }

        enum CodingKeys: String, CodingKey {
            case type, properties, required
            case additionalProperties = "additionalProperties"
        }
    }

    struct Properties: Encodable {
        let reviews: ReviewArray

        init(request: AestheticReviewRequest) {
            reviews = ReviewArray(request: request)
        }
    }

    struct ReviewArray: Encodable {
        let type = "array"
        let items: ReviewItem
        let minItems: Int
        let maxItems: Int

        init(request: AestheticReviewRequest) {
            items = ReviewItem(request: request)
            minItems = request.photos.count
            maxItems = request.photos.count
        }
    }

    struct ReviewItem: Encodable {
        let type = "object"
        let properties: ReviewProperties
        let required = [
            "photo_id",
            "dimensions",
            "reasons",
            "summary",
        ]
        let additionalProperties = false

        init(request: AestheticReviewRequest) {
            properties = ReviewProperties(request: request)
        }

        enum CodingKeys: String, CodingKey {
            case type, properties, required
            case additionalProperties = "additionalProperties"
        }
    }

    struct ReviewProperties: Encodable {
        let photoID: StringProperty
        let dimensions: DimensionsProperty
        let reasons: ReasonsProperty
        let summary: StringProperty

        init(request: AestheticReviewRequest) {
            photoID = StringProperty(
                enumValues: request.photos.map(\.photoID),
                minLength: nil,
                maxLength: nil
            )
            dimensions = DimensionsProperty()
            reasons = ReasonsProperty()
            summary = StringProperty(
                enumValues: nil,
                minLength: 4,
                maxLength: 120
            )
        }

        enum CodingKeys: String, CodingKey {
            case photoID = "photo_id"
            case dimensions, reasons, summary
        }
    }

    struct DimensionsProperty: Encodable {
        let type = "object"
        let properties = DimensionProperties()
        let required = [
            "moment",
            "composition",
            "subject",
            "lighting",
            "storytelling",
        ]
        let additionalProperties = false

        enum CodingKeys: String, CodingKey {
            case type, properties, required
            case additionalProperties = "additionalProperties"
        }
    }

    struct DimensionProperties: Encodable {
        let moment = IntegerProperty(minimum: 0, maximum: 100)
        let composition = IntegerProperty(minimum: 0, maximum: 100)
        let subject = IntegerProperty(minimum: 0, maximum: 100)
        let lighting = IntegerProperty(minimum: 0, maximum: 100)
        let storytelling = IntegerProperty(minimum: 0, maximum: 100)
    }

    struct StringProperty: Encodable {
        let type = "string"
        let enumValues: [String]?
        let minLength: Int?
        let maxLength: Int?

        enum CodingKeys: String, CodingKey {
            case type
            case enumValues = "enum"
            case minLength, maxLength
        }
    }

    struct IntegerProperty: Encodable {
        let type = "integer"
        let minimum: Int
        let maximum: Int
    }

    struct ReasonsProperty: Encodable {
        let type = "array"
        let items = StringProperty(
            enumValues: nil,
            minLength: 2,
            maxLength: 80
        )
        let minItems = 1
        let maxItems = 3
    }
}

private struct MiniMaxChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?
    let baseResponse: BaseResponse?

    enum CodingKeys: String, CodingKey {
        case choices, usage
        case baseResponse = "base_resp"
    }

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let function: Function

        struct Function: Decodable {
            let name: String
            let arguments: String
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    struct BaseResponse: Decodable {
        let statusCode: Int

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
        }
    }
}

private struct MiniMaxReviewPayload: Decodable {
    let reviews: [AestheticReviewEntry]
}
