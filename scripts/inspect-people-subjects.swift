import Foundation

@main
struct PeopleSubjectInspector {
    static func main() {
        let urls = CommandLine.arguments.dropFirst().map {
            URL(fileURLWithPath: $0)
        }
        guard !urls.isEmpty else {
            FileHandle.standardError.write(
                Data("Provide one or more image paths.\n".utf8)
            )
            return
        }

        for url in urls {
            let result = PhotoCategoryClassifier
                .classifyWithEvidence(url)
            print(
                [
                    url.lastPathComponent,
                    result.category.rawValue,
                    String(describing: result.reason),
                    String(format: "%.3f", result.confidence),
                ].joined(separator: "\t")
            )
        }
    }
}
