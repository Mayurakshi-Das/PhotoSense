import Foundation

protocol MediaLibraryProviding: Sendable {
    func authorizationStatus() async -> MediaLibraryAuthorizationStatus
    func requestAuthorization() async -> MediaLibraryAuthorizationStatus
    func fetchAssets() async throws -> [MediaLibraryAsset]
    func fetchFileSize(for assetId: String) async -> Int64?
    func deleteAssets(withIdentifiers ids: [String]) async throws
    func checkAssetsExist(withIdentifiers ids: [String]) async -> Set<String>
}
