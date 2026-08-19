import Foundation

struct DiscoveredAIModel: Equatable, Identifiable {
    let providerID: AIProviderID
    let apiModelID: String
    let displayName: String

    var id: String {
        "\(providerID.rawValue)|\(apiModelID)"
    }
}

enum AIModelDiscoveryError: LocalizedError, Equatable {
    case unsupportedProvider
    case invalidResponse
    case requestRejected(statusCode: Int, providerCode: String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return String(localized: "当前品牌不支持账号模型刷新。")
        case .invalidResponse:
            return String(localized: "模型列表响应无法识别。")
        case let .requestRejected(statusCode, providerCode):
            let detail = providerCode.map { " / \($0)" } ?? ""
            return String(
                localized:
                    "模型列表请求未成功（HTTP \(statusCode)\(detail)）。"
            )
        }
    }
}

struct AIModelDiscoveryService {
    static func supports(_ providerID: AIProviderID) -> Bool {
        providerID == .openAI || providerID == .anthropic
    }

    func discover(
        providerID: AIProviderID,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [DiscoveredAIModel] {
        let request = try makeRequest(
            providerID: providerID,
            apiKey: apiKey
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIModelDiscoveryError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data)
            throw AIModelDiscoveryError.requestRejected(
                statusCode: httpResponse.statusCode,
                providerCode: object.flatMap {
                    SafeProviderErrorCode.find(in: $0)
                }
            )
        }
        return try decode(data, providerID: providerID)
    }

    func makeRequest(
        providerID: AIProviderID,
        apiKey: String
    ) throws -> URLRequest {
        let url: URL
        switch providerID {
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/models")!
        case .anthropic:
            url = URL(
                string: "https://api.anthropic.com/v1/models?limit=1000"
            )!
        default:
            throw AIModelDiscoveryError.unsupportedProvider
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if providerID == .anthropic {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(
                "2023-06-01",
                forHTTPHeaderField: "anthropic-version"
            )
        } else {
            request.setValue(
                "Bearer \(apiKey)",
                forHTTPHeaderField: "Authorization"
            )
        }
        return request
    }

    func decode(
        _ data: Data,
        providerID: AIProviderID
    ) throws -> [DiscoveredAIModel] {
        let response: ModelListResponse
        do {
            response = try JSONDecoder().decode(
                ModelListResponse.self,
                from: data
            )
        } catch {
            throw AIModelDiscoveryError.invalidResponse
        }

        return response.data.compactMap { item in
            let modelID = item.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !modelID.isEmpty,
                  isCandidate(modelID, providerID: providerID) else {
                return nil
            }
            let normalizedDisplayName = item.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DiscoveredAIModel(
                providerID: providerID,
                apiModelID: modelID,
                displayName: normalizedDisplayName?.isEmpty == false
                    ? normalizedDisplayName ?? modelID
                    : modelID
            )
        }
        .uniqued(by: \.apiModelID)
        .sorted {
            $0.displayName.localizedStandardCompare($1.displayName)
                == .orderedAscending
        }
    }

    private func isCandidate(
        _ modelID: String,
        providerID: AIProviderID
    ) -> Bool {
        let normalized = modelID.lowercased()
        switch providerID {
        case .openAI:
            guard normalized.hasPrefix("gpt-") else { return false }
            let excludedTerms = [
                "audio",
                "codex",
                "cyber",
                "daybreak",
                "image",
                "realtime",
                "search",
                "transcribe",
                "tts",
            ]
            guard !excludedTerms.contains(where: normalized.contains) else {
                return false
            }
            guard !normalized.hasSuffix("-pro"),
                  !normalized.contains("-pro-") else {
                return false
            }
            return normalized.range(
                of: #"-\d{4}-\d{2}-\d{2}$"#,
                options: .regularExpression
            ) == nil
        case .anthropic:
            return normalized.hasPrefix("claude-")
        default:
            return false
        }
    }
}

private struct ModelListResponse: Decodable {
    let data: [ModelListItem]
}

private struct ModelListItem: Decodable {
    let id: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private extension Array {
    func uniqued<Key: Hashable>(
        by keyPath: KeyPath<Element, Key>
    ) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
