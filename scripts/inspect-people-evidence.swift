import Foundation

@main
struct PeopleEvidenceInspector {
    static func main() {
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            do {
                let evidence = try PhotoCategoryClassifier
                    .diagnosticEvidence(url)
                let result = PeopleSubjectEvaluator.classify(
                    evidence
                )
                // #region debug-point A:segmentation-only
                report(
                    hypothesisID: "A",
                    location: "inspect-people-evidence.swift:classification",
                    message: "[DEBUG] Segmentation-only evidence",
                    data: evidenceData(
                        url: url,
                        evidence: evidence,
                        result: result
                    )
                )
                // #endregion
                // #region debug-point B:dominant-human
                if maxHumanArea(evidence) >= 0.10 {
                    report(
                        hypothesisID: "B",
                        location: "inspect-people-evidence.swift:dominant-human",
                        message: "[DEBUG] Dominant human evidence",
                        data: evidenceData(
                            url: url,
                            evidence: evidence,
                            result: result
                        )
                    )
                }
                // #endregion
                // #region debug-point C:saliency-overlap
                if !evidence.salientRegions.isEmpty {
                    report(
                        hypothesisID: "C",
                        location: "inspect-people-evidence.swift:saliency",
                        message: "[DEBUG] Saliency geometry",
                        data: evidenceData(
                            url: url,
                            evidence: evidence,
                            result: result
                        )
                    )
                }
                // #endregion
                // #region debug-point D:mask-geometry
                if evidence.personMaskBoundingBox != nil {
                    report(
                        hypothesisID: "D",
                        location: "inspect-people-evidence.swift:mask-geometry",
                        message: "[DEBUG] Mask geometry",
                        data: evidenceData(
                            url: url,
                            evidence: evidence,
                            result: result
                        )
                    )
                }
                // #endregion
                // #region debug-point E:missing-instance
                if !evidence.humanRegions.isEmpty,
                   evidence.personInstanceCount == 0 {
                    report(
                        hypothesisID: "E",
                        location: "inspect-people-evidence.swift:missing-instance",
                        message: "[DEBUG] Human evidence without instance",
                        data: evidenceData(
                            url: url,
                            evidence: evidence,
                            result: result
                        )
                    )
                }
                // #endregion
                print(
                    [
                        url.lastPathComponent,
                        result.category.rawValue,
                        String(describing: result.reason),
                        String(
                            format: "%.3f",
                            result.confidence
                        ),
                        "humans=\(evidence.humanRegions.count)",
                        "maxHuman=\(formatted(maxHumanArea(evidence)))",
                        "faces=\(evidence.faces.count)",
                        "maxFace=\(formatted(maxFaceArea(evidence)))",
                        "mask=\(formatted(evidence.personMaskCoverage))",
                        "instances=\(evidence.personInstanceCount)",
                        "maskBox=\(formattedBox(evidence.personMaskBoundingBox))",
                        "salient=\(evidence.salientRegions.count)",
                        "salientBoxes=\(evidence.salientRegions.map(formattedBox).joined(separator: ";"))",
                    ].joined(separator: "\t")
                )
            } catch {
                print(
                    [
                        url.lastPathComponent,
                        "error",
                        String(describing: error),
                    ].joined(separator: "\t")
                )
            }
        }
    }

    private static func maxHumanArea(
        _ evidence: PeopleSubjectEvidence
    ) -> Double {
        Double(
            evidence.humanRegions.map(\.area).max() ?? 0
        )
    }

    private static func maxFaceArea(
        _ evidence: PeopleSubjectEvidence
    ) -> Double {
        Double(evidence.faces.map(\.area).max() ?? 0)
    }

    private static func evidenceData(
        url: URL,
        evidence: PeopleSubjectEvidence,
        result: PeopleSubjectClassification
    ) -> [String: Any] {
        [
            "filename": url.lastPathComponent,
            "category": result.category.rawValue,
            "reason": String(describing: result.reason),
            "humanCount": evidence.humanRegions.count,
            "maxHumanArea": maxHumanArea(evidence),
            "faceCount": evidence.faces.count,
            "maxFaceArea": maxFaceArea(evidence),
            "maskCoverage": evidence.personMaskCoverage,
            "instanceCount": evidence.personInstanceCount,
            "maskBox": formattedBox(
                evidence.personMaskBoundingBox
            ),
            "salientBoxes": evidence.salientRegions
                .map(formattedBox),
        ]
    }

    // #region debug-point transport
    private static func report(
        hypothesisID: String,
        location: String,
        message: String,
        data: [String: Any]
    ) {
        let envURL = URL(fileURLWithPath:
            ".dbg/people-false-positives.env"
        )
        guard let content = try? String(
            contentsOf: envURL,
            encoding: .utf8
        ),
              let endpoint = content
                .split(separator: "\n")
                .first(where: {
                    $0.hasPrefix("DEBUG_SERVER_URL=")
                })?
                .split(separator: "=", maxSplits: 1)
                .last,
              let url = URL(string: String(endpoint)) else {
            return
        }
        let payload: [String: Any] = [
            "sessionId": "people-false-positives",
            "runId": ProcessInfo.processInfo.environment[
                "TRAE_DEBUG_RUN_ID"
            ] ?? "pre-fix",
            "hypothesisId": hypothesisID,
            "location": location,
            "msg": message,
            "data": data,
            "ts": Int(Date().timeIntervalSince1970 * 1_000),
        ]
        guard let body = try? JSONSerialization.data(
            withJSONObject: payload
        ) else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) {
            _, _, _ in semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
    }
    // #endregion

    private static func formatted(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    private static func formattedBox(
        _ box: CGRect?
    ) -> String {
        guard let box else { return "none" }
        return [
            formatted(Double(box.minX)),
            formatted(Double(box.minY)),
            formatted(Double(box.width)),
            formatted(Double(box.height)),
        ].joined(separator: ",")
    }
}
