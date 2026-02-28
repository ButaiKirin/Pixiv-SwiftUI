import Foundation
import Observation

@Observable
@MainActor
final class IllustSeriesStore {
    let seriesId: Int

    var seriesDetail: IllustSeriesDetail?
    var illusts: [Illusts] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var nextUrl: String?

    init(seriesId: Int) {
        self.seriesId = seriesId
    }

    func fetch() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let illustAPI = PixivAPI.shared.illustAPI else {
                throw NetworkError.invalidURL // Using invalidURL as a placeholder if API is not initialized
            }

            let response = try await illustAPI.getIllustSeries(seriesId: seriesId)

            seriesDetail = response.illustSeriesDetail
            illusts = response.illusts
            nextUrl = response.nextUrl

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func loadMore() async {
        guard !isLoadingMore, let nextUrl = nextUrl else { return }

        isLoadingMore = true

        do {
            guard let illustAPI = PixivAPI.shared.illustAPI else {
                throw NetworkError.invalidURL
            }

            let response = try await illustAPI.getIllustSeriesByURL(nextUrl)

            illusts.append(contentsOf: response.illusts)
            self.nextUrl = response.nextUrl

            isLoadingMore = false
        } catch {
            errorMessage = error.localizedDescription
            isLoadingMore = false
        }
    }
}
