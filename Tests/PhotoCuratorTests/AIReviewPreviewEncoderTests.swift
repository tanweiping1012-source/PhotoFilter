import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import PhotoCurator

final class AIReviewPreviewEncoderTests: XCTestCase {
    func testEachPreviewSizeProducesItsExactLongestEdge() throws {
        let sourceURL = try makeSourceJPEG(width: 1_800, height: 1_200)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        for size in AIReviewPreviewSize.allCases {
            let data = try AIReviewPreviewEncoder.jpegData(
                for: sourceURL,
                maximumPixelSize: size.maximumPixelSize
            )
            let properties = try imageProperties(from: data)
            let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
            let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)

            XCTAssertEqual(
                max(width, height),
                size.maximumPixelSize,
                "\(size.rawValue) did not produce the configured longest edge."
            )
        }
    }

    func testEncodedPreviewDoesNotCopyGPSMetadata() throws {
        let sourceURL = try makeSourceJPEG(width: 1_800, height: 1_200)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let data = try AIReviewPreviewEncoder.jpegData(
            for: sourceURL,
            maximumPixelSize: AIReviewPreviewSize.large.maximumPixelSize
        )
        let properties = try imageProperties(from: data)

        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    private func makeSourceJPEG(width: Int, height: Int) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.setFillColor(
            CGColor(
                red: 0.15,
                green: 0.55,
                blue: 0.72,
                alpha: 1
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-curator-preview-\(UUID().uuidString).jpg")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.jpeg" as CFString,
                1,
                nil
            )
        )
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 39.9042,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 116.4074,
            kCGImagePropertyGPSLongitudeRef: "E",
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyGPSDictionary: gps] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func imageProperties(from data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        )
    }
}
