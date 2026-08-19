import Foundation

struct AestheticReviewUsage: Equatable {
    let inputTokens: Int?
    let outputTokens: Int?

    var summary: String? {
        switch (inputTokens, outputTokens) {
        case let (input?, output?):
            String(localized: "本次 AI 调用：输入 \(input) tokens，输出 \(output) tokens。费用以所选供应商账单为准。")
        case let (input?, nil):
            String(localized: "本次 AI 调用：输入 \(input) tokens。费用以所选供应商账单为准。")
        case let (nil, output?):
            String(localized: "本次 AI 调用：输出 \(output) tokens。费用以所选供应商账单为准。")
        case (nil, nil):
            nil
        }
    }
}

struct AestheticReviewResult: Equatable {
    let response: AestheticReviewResponse
    let usage: AestheticReviewUsage
}

enum AestheticReviewResponseFailureStage: Equatable {
    case transportEnvelope
    case responseEnvelope
    case missingReviewPayload
    case reviewPayloadSchema

    var userFacingDescription: String {
        switch self {
        case .transportEnvelope:
            String(localized: "AI 服务返回的网络响应无法识别")
        case .responseEnvelope:
            String(localized: "AI 服务返回的响应外层结构无法识别")
        case .missingReviewPayload:
            String(localized: "AI 服务未返回要求的工具调用或 JSON 结果")
        case .reviewPayloadSchema:
            String(localized: "AI 服务返回的审美字段不完整或类型不符")
        }
    }
}

enum AestheticReviewClientError: LocalizedError, Equatable {
    case invalidConfiguration
    case incompletePreviewSet
    case invalidResponse(stage: AestheticReviewResponseFailureStage)
    case requestRejected(statusCode: Int, providerCode: String?)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return String(localized: "当前 AI 模型配置不完整，未发送请求。")
        case .incompletePreviewSet:
            return String(localized: "候选缩略图不完整，未发送请求。")
        case let .invalidResponse(stage):
            return String(localized: "\(stage.userFacingDescription)，已丢弃本次评分。")
        case let .requestRejected(statusCode, providerCode):
            let providerDetail = providerCode.map { " / \($0)" } ?? ""
            if providerCode == "MiniMax-TokenPlan-RateLimit" {
                return String(localized: "MiniMax Token Plan 当前未接受请求（HTTP \(statusCode)）。这通常表示 5 小时额度、周额度或动态限流；请在 MiniMax 套餐用量中检查可用资源，或至少等待 1 分钟后重试。")
            }
            if statusCode == 429 {
                return String(localized: "AI 服务当前已限流或账户资源暂不可用（HTTP \(statusCode)\(providerDetail)）。请检查供应商的套餐额度或余额，并至少等待 1 分钟后重试。")
            }
            return String(localized: "AI 服务请求未成功（HTTP \(statusCode)\(providerDetail)）。请检查供应商、模型权限、模型 ID 或稍后重试。")
        }
    }
}

struct AestheticReviewPreview: Equatable, Sendable {
    let opaquePhotoID: String
    let jpegData: Data
}

typealias ArkAestheticReviewUsage = AestheticReviewUsage
typealias ArkAestheticReviewResult = AestheticReviewResult
typealias ArkAestheticReviewResponseFailureStage = AestheticReviewResponseFailureStage
typealias ArkAestheticReviewClientError = AestheticReviewClientError
typealias ArkAestheticReviewPreview = AestheticReviewPreview

/// 只调用火山方舟 Responses API；请求内容只有匿名 ID、评审指令和用户确认尺寸的内存 JPEG。
struct ArkAestheticReviewClient {
    let model: AIModelDescriptor

    init(
        model: AIModelDescriptor = AIModelCatalog.model(
            for: .doubaoSeed20Lite
        )
    ) {
        self.model = model
    }

    func review(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> AestheticReviewResult {
        var urlRequest = try makeURLRequest(request: request, previews: previews, apiKey: apiKey)
        urlRequest.timeoutInterval = 90

        let (data, urlResponse) = try await session.data(for: urlRequest)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw ArkAestheticReviewClientError.invalidResponse(stage: .transportEnvelope)
        }
        guard (200...299).contains(response.statusCode) else {
            throw ArkAestheticReviewClientError.requestRejected(
                statusCode: response.statusCode,
                providerCode: providerErrorCode(from: data)
            )
        }
        return try decodeResponse(data, request: request)
    }

    func makeURLRequest(
        request: AestheticReviewRequest,
        previews: [AestheticReviewPreview],
        apiKey: String
    ) throws -> URLRequest {
        let expectedIDs = request.photos.map(\.photoID)
        let previewIDs = previews.map(\.opaquePhotoID)
        guard previews.count == expectedIDs.count,
              Set(previewIDs).count == previewIDs.count,
              Set(previewIDs) == Set(expectedIDs) else {
            throw ArkAestheticReviewClientError.incompletePreviewSet
        }

        let previewByID = Dictionary(uniqueKeysWithValues: previews.map { ($0.opaquePhotoID, $0) })
        let userContent: [ArkResponseInputContent] = [
            .text(AestheticReviewPrompt.combinedPrompt(for: request)),
        ] + request.photos.compactMap { input in
            guard let preview = previewByID[input.photoID] else { return nil }
            return .image(dataURL: "data:image/jpeg;base64,\(preview.jpegData.base64EncodedString())")
        }

        let body = ArkResponsesRequestBody(
            model: model.apiModelID,
            input: [
                ArkResponseInput(role: "user", content: userContent),
            ],
            tools: [ArkResponseReviewTool(request: request)],
            toolChoice: "required",
            temperature: 0.1,
            // 五维评分和总结会显著增加 JSON 长度，需给 5 张图的闭合结果留足空间。
            maxOutputTokens: AestheticReviewPrompt.maximumOutputTokens,
            store: false
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
        let completion: ArkResponsesResponse
        do {
            completion = try JSONDecoder().decode(ArkResponsesResponse.self, from: data)
        } catch {
            throw ArkAestheticReviewClientError.invalidResponse(stage: .responseEnvelope)
        }
        let functionArguments = completion.output.first(where: {
            $0.type == "function_call" && $0.name == ArkResponseReviewTool.name
        })?.arguments
        let outputText = completion.output
            .flatMap({ $0.content ?? [] })
            .filter({ $0.type == "output_text" })
            .compactMap(\.text)
            .joined()
        guard let payloadData = functionArguments.flatMap(normalizedJSONData)
            ?? (outputText.isEmpty ? nil : normalizedJSONData(from: outputText)) else {
            throw ArkAestheticReviewClientError.invalidResponse(stage: .missingReviewPayload)
        }
        let payload: ArkReviewPayload
        do {
            payload = try JSONDecoder().decode(ArkReviewPayload.self, from: payloadData)
        } catch {
            throw ArkAestheticReviewClientError.invalidResponse(stage: .reviewPayloadSchema)
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
                inputTokens: completion.usage?.inputTokens,
                outputTokens: completion.usage?.outputTokens
            )
        )
    }

    /// 只提取方舟错误 JSON 中短小的机器错误码；不展示 message/detail，避免界面或日志意外回显请求内容。
    func providerErrorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findSafeErrorCode(in: object)
    }

    private func normalizedJSONData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
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
        if let wrappedData = unfenced.data(using: .utf8),
           let unwrapped = try? JSONDecoder().decode(String.self, from: wrappedData) {
            return normalizedJSONData(from: unwrapped)
        }

        // 部分兼容模型会在合法 JSON 前后加一句说明。这里只裁出最外层对象；
        // 后续仍会执行 Codable 解码、photo_id 白名单、分数与理由范围校验。
        guard let firstBrace = unfenced.firstIndex(of: "{"),
              let lastBrace = unfenced.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        let json = String(unfenced[firstBrace...lastBrace])
        return json.data(using: .utf8)
    }

    private func findSafeErrorCode(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where key.lowercased() == "code" || key.lowercased() == "errorcode" {
                if let candidate = value as? String, isSafeErrorCode(candidate) {
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
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }
    }
}

enum AestheticReviewPrompt {
    static let maximumOutputTokens = 1_600

    static let systemPrompt = """
    你是旅行照片评分助手。必须使用固定的绝对标尺，独立评估每张图片的瞬间、构图、主体、光线和叙事表现，再给出总分。一次附带多张图片只为传输效率，不代表候选组；不得比较图片，不得返回名次，不得在评价中使用“本组、相比、更好、更差、优先、候补”等相对表述。不得杜撰图片外的信息，不得评价人物身份或敏感属性。必须且只能调用 submit_photo_reviews 工具一次提交结果。
    """

    static let jsonSystemPrompt = """
    你是旅行照片评分助手。必须使用固定的绝对标尺，独立评估每张图片的瞬间、构图、主体、光线和叙事表现，再给出总分。一次附带多张图片只为传输效率，不代表候选组；不得比较图片，不得返回名次，不得在评价中使用“本组、相比、更好、更差、优先、候补”等相对表述。不得杜撰图片外的信息，不得评价人物身份或敏感属性。只返回用户要求的 JSON 对象，不要添加 Markdown 或解释。
    """

    static func userPrompt(for request: AestheticReviewRequest) -> String {
        let identifiers = request.photos.map { "\($0.photoID)（图片 \($0.position)）" }.joined(separator: "、")
        let categoryInstruction = request.scope.category?.scoringInstruction
            ?? String(
                localized:
                    "本次未指定人物或风景类型；只按照片自身内容使用固定标尺评分。"
            )
        return """
        请独立评分以下 \(request.photos.count) 张匿名照片：\(identifiers)。图片会按此顺序附在文本后。不要让其中任何一张照片影响另一张的分数或评价。
        \(categoryInstruction)
        所有请求统一使用以下绝对标尺：90–100 为少见且完成度很高；80–89 为明显优秀，主体、瞬间或叙事有突出表现；70–79 为整体可用但仍有明确不足；60–69 为存在明显画面或表达问题；0–59 为严重技术问题，或缺少有效主体与表达。
        返回且仅返回此 JSON：
        {"reviews":[{"photo_id":"photo_001","score":90,"dimensions":{"moment":92,"composition":88,"subject":93,"lighting":86,"storytelling":89},"reasons":["主体明确且层次清楚","瞬间具有旅途感"],"summary":"主体、光线和叙事表现完整，画面完成度高。"}]}
        规则：每个 photo_id 必须恰好出现一次；不得返回 rank 或任何名次字段；score 和 dimensions 的五项分数都必须是 0 到 100 的整数；score 是基于固定标尺的综合判断，不要求等于五维平均值；reasons 必须包含 1 到 3 条、每条 2 到 80 个字符的具体中文评价；summary 必须是 4 到 120 个字符的中文总结，且只能评价当前照片自身。不得增加任何其它字段。
        """
    }

    static func combinedPrompt(for request: AestheticReviewRequest) -> String {
        "\(systemPrompt)\n\n\(userPrompt(for: request))"
    }
}

private struct ArkResponsesRequestBody: Encodable {
    let model: String
    let input: [ArkResponseInput]
    let tools: [ArkResponseReviewTool]
    let toolChoice: String
    let temperature: Double
    let maxOutputTokens: Int
    let store: Bool
    let thinking = ArkResponseThinking(type: "disabled")

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case tools
        case toolChoice = "tool_choice"
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case store
        case thinking
    }
}

private struct ArkResponseReviewTool: Encodable {
    static let name = "submit_photo_reviews"

    let type = "function"
    let name = Self.name
    let description = "提交每张照片基于统一绝对标尺的独立评分。"
    let parameters: Parameters
    let strict = true

    init(request: AestheticReviewRequest) {
        parameters = Parameters(request: request)
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

        enum CodingKeys: String, CodingKey {
            case type, items
            case minItems = "minItems"
            case maxItems = "maxItems"
        }
    }

    struct ReviewItem: Encodable {
        let type = "object"
        let properties: ReviewProperties
        let required = [
            "photo_id",
            "score",
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
        let photoID: PhotoID
        let score = IntegerRange(minimum: 0, maximum: 100)
        let dimensions = Dimensions()
        let reasons = Reasons()
        let summary = StringRange(minLength: 4, maxLength: 120)

        init(request: AestheticReviewRequest) {
            photoID = PhotoID(values: request.photos.map(\.photoID))
        }

        enum CodingKeys: String, CodingKey {
            case photoID = "photo_id"
            case score, dimensions, reasons, summary
        }
    }

    struct Dimensions: Encodable {
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
        let moment = IntegerRange(minimum: 0, maximum: 100)
        let composition = IntegerRange(minimum: 0, maximum: 100)
        let subject = IntegerRange(minimum: 0, maximum: 100)
        let lighting = IntegerRange(minimum: 0, maximum: 100)
        let storytelling = IntegerRange(minimum: 0, maximum: 100)
    }

    struct PhotoID: Encodable {
        let type = "string"
        let values: [String]

        enum CodingKeys: String, CodingKey {
            case type
            case values = "enum"
        }
    }

    struct IntegerRange: Encodable {
        let type = "integer"
        let minimum: Int
        let maximum: Int
    }

    struct Reasons: Encodable {
        let type = "array"
        let items = StringRange(minLength: 2, maxLength: 80)
        let minItems = 1
        let maxItems = 3

        enum CodingKeys: String, CodingKey {
            case type, items
            case minItems = "minItems"
            case maxItems = "maxItems"
        }
    }

    struct StringRange: Encodable {
        let type = "string"
        let minLength: Int
        let maxLength: Int

        enum CodingKeys: String, CodingKey {
            case type
            case minLength = "minLength"
            case maxLength = "maxLength"
        }
    }
}

private struct ArkResponseThinking: Encodable {
    let type: String
}

private struct ArkResponseInput: Encodable {
    let role: String
    let content: [ArkResponseInputContent]
}

private enum ArkResponseInputContent: Encodable {
    case text(String)
    case image(dataURL: String)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode("input_text", forKey: .type)
            try container.encode(value, forKey: .text)
        case let .image(dataURL):
            try container.encode("input_image", forKey: .type)
            try container.encode(dataURL, forKey: .imageURL)
        }
    }
}

private struct ArkResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        let type: String?
        let name: String?
        let arguments: String?
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let type: String?
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    let output: [OutputItem]
    let usage: Usage?
}

private struct ArkReviewPayload: Decodable {
    let reviews: [AestheticReviewEntry]
}
