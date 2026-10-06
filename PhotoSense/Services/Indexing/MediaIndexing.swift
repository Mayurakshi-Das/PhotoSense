import Foundation

protocol MediaIndexing: Sendable {
    func buildIndex() async throws -> MediaIndexSnapshot
}
