import Foundation
import XCTest
@testable import PhotoCurator

final class PeopleSubjectClassifierTests: XCTestCase {
    func testTinyBackgroundPersonRemainsScenery() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [
                    region(x: 0.80, y: 0.30, width: 0.05, height: 0.10),
                ],
                faces: [
                    face(x: 0.815, y: 0.375, width: 0.015, height: 0.02),
                ]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testClearFrontFacingPortraitIsPeople() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [
                    region(x: 0.28, y: 0.08, width: 0.44, height: 0.80),
                ],
                faces: [
                    face(
                        x: 0.40,
                        y: 0.60,
                        width: 0.20,
                        height: 0.22,
                        quality: 0.72,
                        yaw: 0.08
                    ),
                ]
            )
        )

        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.reason, .clearPortrait)
    }

    func testClearSideFacingPortraitIsPeople() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [
                    region(x: 0.32, y: 0.10, width: 0.36, height: 0.72),
                ],
                faces: [
                    face(
                        x: 0.42,
                        y: 0.57,
                        width: 0.17,
                        height: 0.18,
                        quality: 0.42,
                        yaw: 1.20
                    ),
                ]
            )
        )

        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.reason, .clearPortrait)
    }

    func testLargeFacelessPersonIsStillSubject() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [
                    region(x: 0.24, y: 0.08, width: 0.46, height: 0.64),
                ],
                personMaskCoverage: 0.18,
                personMaskBoundingBox: CGRect(
                    x: 0.25,
                    y: 0.09,
                    width: 0.44,
                    height: 0.62
                ),
                personInstanceCount: 1
            )
        )

        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.reason, .dominantPerson)
    }

    func testSalientPersonInLandscapeIsPeople() {
        let person = region(
            x: 0.18,
            y: 0.12,
            width: 0.14,
            height: 0.34
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [person],
                personMaskCoverage: 0.026,
                personMaskBoundingBox: person.boundingBox,
                salientRegions: [
                    CGRect(x: 0.16, y: 0.10, width: 0.19, height: 0.40),
                ]
            )
        )

        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.reason, .personInLandscape)
    }

    func testSegmentationOnlySilhouetteCanBePeople() {
        let maskBox = CGRect(
            x: 0.62,
            y: 0.10,
            width: 0.11,
            height: 0.31
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                personMaskCoverage: 0.018,
                personMaskBoundingBox: maskBox,
                personInstanceCount: 1,
                salientRegions: [
                    CGRect(x: 0.60, y: 0.08, width: 0.16, height: 0.36),
                ]
            )
        )

        XCTAssertEqual(result.category, .people)
        XCTAssertEqual(result.reason, .personInLandscape)
    }

    func testSegmentationOnlyWithoutInstanceRemainsScenery() {
        let maskBox = CGRect(
            x: 0.62,
            y: 0.10,
            width: 0.11,
            height: 0.31
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                personMaskCoverage: 0.018,
                personMaskBoundingBox: maskBox,
                salientRegions: [maskBox]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testHorizontalSegmentationOnlyMaskRemainsScenery() {
        let maskBox = CGRect(
            x: 0.25,
            y: 0.30,
            width: 0.40,
            height: 0.12
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                personMaskCoverage: 0.025,
                personMaskBoundingBox: maskBox,
                personInstanceCount: 1,
                salientRegions: [maskBox]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testDominantHumanWithoutMaskSupportRemainsScenery() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.10,
                        y: 0.08,
                        width: 0.78,
                        height: 0.88
                    ),
                ],
                personInstanceCount: 1
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testBroadSaliencyNeedsMeaningfulPersonConcentration() {
        let person = region(
            x: 0.45,
            y: 0.30,
            width: 0.12,
            height: 0.12
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [person],
                personMaskCoverage: 0.015,
                personMaskBoundingBox: person.boundingBox,
                salientRegions: [
                    CGRect(x: 0, y: 0, width: 1, height: 1),
                ]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testSmallPersonWithoutSaliencyRemainsScenery() {
        let person = region(
            x: 0.18,
            y: 0.12,
            width: 0.14,
            height: 0.34
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [person],
                personMaskCoverage: 0.026,
                personMaskBoundingBox: person.boundingBox,
                salientRegions: [
                    CGRect(x: 0.65, y: 0.50, width: 0.24, height: 0.30),
                ]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testBackgroundCrowdRemainsScenery() {
        let people = [
            region(x: 0.10, y: 0.15, width: 0.08, height: 0.20),
            region(x: 0.28, y: 0.14, width: 0.08, height: 0.20),
            region(x: 0.55, y: 0.16, width: 0.08, height: 0.20),
            region(x: 0.76, y: 0.15, width: 0.08, height: 0.20),
        ]
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: people,
                personMaskCoverage: 0.05,
                salientRegions: [
                    CGRect(x: 0.05, y: 0.10, width: 0.82, height: 0.30),
                ]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testMergedCrowdMaskUsesInstanceCountAndRemainsScenery() {
        let maskBox = CGRect(
            x: 0.12,
            y: 0.12,
            width: 0.72,
            height: 0.30
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                personMaskCoverage: 0.07,
                personMaskBoundingBox: maskBox,
                personInstanceCount: 5,
                salientRegions: [maskBox]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testExtremeEdgeSilhouetteRemainsScenery() {
        let person = region(
            x: 0,
            y: 0.15,
            width: 0.08,
            height: 0.28
        )
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence(
                humanRegions: [person],
                personMaskCoverage: 0.018,
                salientRegions: [
                    CGRect(x: 0, y: 0.12, width: 0.10, height: 0.34),
                ]
            )
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .incidentalPeople)
    }

    func testObservedStreetSceneFalsePositivesRemainScenery() {
        let cases = [
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.7188,
                        y: 0.1836,
                        width: 0.0863,
                        height: 0.2500,
                        confidence: 0.7292
                    ),
                ],
                personMaskCoverage: 0.0087,
                personMaskBoundingBox: CGRect(
                    x: 0.7305,
                    y: 0.1979,
                    width: 0.0664,
                    height: 0.2292
                ),
                personInstanceCount: 1,
                salientRegions: [
                    CGRect(
                        x: 0.1246,
                        y: 0.1729,
                        width: 0.7817,
                        height: 0.5151
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.1870,
                        y: 0.0699,
                        width: 0.1099,
                        height: 0.1957,
                        confidence: 0.6769
                    ),
                ],
                personMaskCoverage: 0.0154,
                personMaskBoundingBox: CGRect(
                    x: 0.1927,
                    y: 0.0742,
                    width: 0.1042,
                    height: 0.1914
                ),
                salientRegions: [
                    CGRect(
                        x: 0.0734,
                        y: 0.0532,
                        width: 0.7967,
                        height: 0.8329
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.0431,
                        y: 0.2281,
                        width: 0.0599,
                        height: 0.2216,
                        confidence: 0.5796
                    ),
                ],
                personMaskCoverage: 0.0122,
                personMaskBoundingBox: CGRect(
                    x: 0.0508,
                    y: 0.2292,
                    width: 0.1992,
                    height: 0.2083
                ),
                salientRegions: [
                    CGRect(
                        x: 0,
                        y: 0.2349,
                        width: 0.9604,
                        height: 0.4656
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.3080,
                        y: 0.1299,
                        width: 0.0543,
                        height: 0.2426,
                        confidence: 0.6675
                    ),
                ],
                personMaskCoverage: 0.0073,
                personMaskBoundingBox: CGRect(
                    x: 0.3164,
                    y: 0.1250,
                    width: 0.0430,
                    height: 0.2344
                ),
                salientRegions: [
                    CGRect(
                        x: 0.1227,
                        y: 0.1387,
                        width: 0.8773,
                        height: 0.5630
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.3127,
                        y: 0.1086,
                        width: 0.0514,
                        height: 0.2469,
                        confidence: 0.6536
                    ),
                ],
                personMaskCoverage: 0.0076,
                personMaskBoundingBox: CGRect(
                    x: 0.3164,
                    y: 0.1146,
                    width: 0.0469,
                    height: 0.2188
                ),
                salientRegions: [
                    CGRect(
                        x: 0.1128,
                        y: 0.1260,
                        width: 0.8726,
                        height: 0.5806
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.8984,
                        y: 0.1497,
                        width: 0.0781,
                        height: 0.3377,
                        confidence: 0.6583
                    ),
                    region(
                        x: 0.8462,
                        y: 0.1472,
                        width: 0.0674,
                        height: 0.3191,
                        confidence: 0.6501
                    ),
                ],
                personMaskCoverage: 0.0342,
                personMaskBoundingBox: CGRect(
                    x: 0.2148,
                    y: 0.1458,
                    width: 0.7617,
                    height: 0.3438
                ),
                personInstanceCount: 1,
                salientRegions: [
                    CGRect(
                        x: 0.0003,
                        y: 0.2534,
                        width: 0.9997,
                        height: 0.4253
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                personMaskCoverage: 0.0201,
                personMaskBoundingBox: CGRect(
                    x: 0.6211,
                    y: 0.0938,
                    width: 0.0859,
                    height: 0.3229
                ),
                personInstanceCount: 1,
                salientRegions: [
                    CGRect(
                        x: 0,
                        y: 0.1968,
                        width: 0.8564,
                        height: 0.4399
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.5598,
                        y: 0.2511,
                        width: 0.0703,
                        height: 0.3009,
                        confidence: 0.5796
                    ),
                ],
                personMaskCoverage: 0.0250,
                personMaskBoundingBox: CGRect(
                    x: 0.4766,
                    y: 0.2552,
                    width: 0.2109,
                    height: 0.2760
                ),
                personInstanceCount: 2,
                salientRegions: [
                    CGRect(
                        x: 0.0494,
                        y: 0.2783,
                        width: 0.7469,
                        height: 0.4514
                    ),
                ]
            ),
            PeopleSubjectEvidence(
                humanRegions: [
                    region(
                        x: 0.6774,
                        y: 0.3191,
                        width: 0.0539,
                        height: 0.2056,
                        confidence: 0.5964
                    ),
                    region(
                        x: 0.5477,
                        y: 0.2826,
                        width: 0.0543,
                        height: 0.2608,
                        confidence: 0.5638
                    ),
                ],
                personMaskCoverage: 0.0240,
                personMaskBoundingBox: CGRect(
                    x: 0.5430,
                    y: 0.2865,
                    width: 0.1953,
                    height: 0.2396
                ),
                personInstanceCount: 1,
                salientRegions: [
                    CGRect(
                        x: 0.0401,
                        y: 0.2793,
                        width: 0.8124,
                        height: 0.4639
                    ),
                ]
            ),
        ]

        for evidence in cases {
            let result = PeopleSubjectEvaluator.classify(evidence)
            XCTAssertEqual(result.category, .scenery)
            XCTAssertEqual(result.reason, .incidentalPeople)
        }
    }

    func testNoPersonSignalIsScenery() {
        let result = PeopleSubjectEvaluator.classify(
            PeopleSubjectEvidence()
        )

        XCTAssertEqual(result.category, .scenery)
        XCTAssertEqual(result.reason, .noPerson)
    }

    private func region(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        confidence: Float = 0.90
    ) -> PeopleSubjectRegion {
        PeopleSubjectRegion(
            boundingBox: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            confidence: confidence
        )
    }

    private func face(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        quality: Float = 0.60,
        yaw: Double = 0
    ) -> PeopleFaceEvidence {
        PeopleFaceEvidence(
            boundingBox: CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            captureQuality: quality,
            yawRadians: yaw
        )
    }
}
