import Foundation

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "hikki-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
