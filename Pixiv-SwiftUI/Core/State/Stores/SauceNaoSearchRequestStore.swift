import Foundation

@MainActor
final class SauceNaoSearchRequestStore {
    static let shared = SauceNaoSearchRequestStore()

    private var requests: [UUID: SauceNaoSearchRequest] = [:]

    private init() {}

    func enqueue(imageData: Data, fileName: String) -> UUID {
        let requestId = UUID()
        requests[requestId] = SauceNaoSearchRequest(imageData: imageData, fileName: fileName)
        return requestId
    }

    func consume(requestId: UUID) -> SauceNaoSearchRequest? {
        defer { requests.removeValue(forKey: requestId) }
        return requests[requestId]
    }
}

struct SauceNaoSearchRequest {
    let imageData: Data
    let fileName: String
}
