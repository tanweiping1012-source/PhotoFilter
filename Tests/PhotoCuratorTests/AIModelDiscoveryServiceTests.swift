import Foundation
import XCTest

@testable import PhotoCurator

final class AIModelDiscoveryServiceTests: XCTestCase {
    func testOpenAIDiscoveryFiltersSpecializedAndSnapshotModels()
        throws {
        let data = Data(
            """
            {"data":[
              {"id":"gpt-5.6-sol"},
              {"id":"gpt-5.6-terra"},
              {"id":"gpt-5.6-sol-2026-07-09"},
              {"id":"gpt-5.6-cyber"},
              {"id":"gpt-image-2"},
              {"id":"gpt-realtime-2.1"},
              {"id":"text-embedding-4"}
            ]}
            """.utf8
        )

        let models = try AIModelDiscoveryService().decode(
            data,
            providerID: .openAI
        )

        XCTAssertEqual(
            models.map(\.apiModelID),
            ["gpt-5.6-sol", "gpt-5.6-terra"]
        )
    }

    func testAnthropicDiscoveryUsesAccountDisplayNames() throws {
        let data = Data(
            """
            {"data":[
              {"id":"claude-opus-5","display_name":"Claude Opus 5"},
              {"id":"claude-fable-5","display_name":"Claude Fable 5"},
              {"id":"embedding-model","display_name":"Embedding"}
            ]}
            """.utf8
        )

        let models = try AIModelDiscoveryService().decode(
            data,
            providerID: .anthropic
        )

        XCTAssertEqual(
            models.map(\.apiModelID),
            ["claude-fable-5", "claude-opus-5"]
        )
        XCTAssertEqual(
            models.map(\.displayName),
            ["Claude Fable 5", "Claude Opus 5"]
        )
    }

    func testDiscoveryRequestsUseProviderAuthentication() throws {
        let service = AIModelDiscoveryService()
        let openAI = try service.makeRequest(
            providerID: .openAI,
            apiKey: "openai-secret"
        )
        XCTAssertEqual(
            openAI.url?.absoluteString,
            "https://api.openai.com/v1/models"
        )
        XCTAssertEqual(
            openAI.value(forHTTPHeaderField: "Authorization"),
            "Bearer openai-secret"
        )

        let anthropic = try service.makeRequest(
            providerID: .anthropic,
            apiKey: "anthropic-secret"
        )
        XCTAssertEqual(
            anthropic.url?.absoluteString,
            "https://api.anthropic.com/v1/models?limit=1000"
        )
        XCTAssertEqual(
            anthropic.value(forHTTPHeaderField: "x-api-key"),
            "anthropic-secret"
        )
        XCTAssertEqual(
            anthropic.value(
                forHTTPHeaderField: "anthropic-version"
            ),
            "2023-06-01"
        )
    }
}
