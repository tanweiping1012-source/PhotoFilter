import Foundation
import XCTest

@testable import PhotoCurator

final class AIModelConnectionVerifierTests: XCTestCase {
    func testVerificationUsesImageRequestAndFormalValidator() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            SuccessfulConnectionURLProtocol.self,
        ]
        let session = URLSession(configuration: configuration)
        let imageURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        .appendingPathComponent(
            "Resources/DemoPhotos/demo-01-coastal-road.jpg"
        )

        try await AIModelConnectionVerifier().verify(
            model: AIModelCatalog.model(for: .moonshotKimiK25),
            apiKey: "connection-test-key",
            session: session,
            testImageURL: imageURL
        )

        let request = try XCTUnwrap(
            SuccessfulConnectionURLProtocol.lastRequest
        )
        let body = try XCTUnwrap(
            SuccessfulConnectionURLProtocol.lastBody
        )
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyText.contains("\"model\":\"kimi-k2.5\""))
        XCTAssertTrue(bodyText.contains("\"image_url\""))
        XCTAssertTrue(bodyText.contains("base64,"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer connection-test-key"
        )
        XCTAssertFalse(bodyText.contains("connection-test-key"))
    }

    func testVerificationRejectsResponseOutsideFormalContract()
        async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [
            InvalidConnectionURLProtocol.self,
        ]
        let session = URLSession(configuration: configuration)
        let imageURL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        .appendingPathComponent(
            "Resources/DemoPhotos/demo-01-coastal-road.jpg"
        )

        do {
            try await AIModelConnectionVerifier().verify(
                model: AIModelCatalog.model(for: .moonshotKimiK25),
                apiKey: "connection-test-key",
                session: session,
                testImageURL: imageURL
            )
            XCTFail("Invalid model output must not verify.")
        } catch {
            XCTAssertTrue(error is AestheticReviewValidationError)
        }
    }
}

private final class SuccessfulConnectionURLProtocol:
    URLProtocol,
    @unchecked Sendable {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.flatMap {
            stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4_096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(
                capacity: bufferSize
            )
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(
                    buffer,
                    maxLength: bufferSize
                )
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
        complete(
            content: """
            {"reviews":[{"photo_id":"photo_001","score":88,"dimensions":{"moment":87,"composition":89,"subject":90,"lighting":86,"storytelling":88},"reasons":["主体清楚且构图稳定"],"summary":"主体、光线和叙事表现完整，画面完成度高。"}]}
            """
        )
    }

    override func stopLoading() {}

    private func complete(content: String) {
        let escaped = try! String(
            data: JSONEncoder().encode(content),
            encoding: .utf8
        )!
        let data = Data(
            """
            {"choices":[{"message":{"content":\(escaped)}}],"usage":{"prompt_tokens":100,"completion_tokens":40}}
            """.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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
}

private final class InvalidConnectionURLProtocol:
    URLProtocol,
    @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let content = """
        {"reviews":[{"photo_id":"photo_001","score":188,"dimensions":{"moment":87,"composition":89,"subject":90,"lighting":86,"storytelling":88},"reasons":["主体清楚且构图稳定"],"summary":"主体、光线和叙事表现完整，画面完成度高。"}]}
        """
        let escaped = try! String(
            data: JSONEncoder().encode(content),
            encoding: .utf8
        )!
        let data = Data(
            """
            {"choices":[{"message":{"content":\(escaped)}}]}
            """.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
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
