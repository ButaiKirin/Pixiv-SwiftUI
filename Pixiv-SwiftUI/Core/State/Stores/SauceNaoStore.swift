import Observation
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
@Observable
final class SauceNaoStore {
    var isSearching = false
    var results: [SauceNaoMatch] = []
    var errorMessage: String?

    private let api = SauceNAOAPI()

    func search(imageData: Data, fileName: String = "image.jpg") async {
        isSearching = true
        errorMessage = nil
        results = []
        defer { isSearching = false }

        let compressedData = compressImageIfNeeded(imageData) ?? imageData

        do {
            results = try await api.searchMatches(imageData: compressedData, fileName: fileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compressImageIfNeeded(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width < 720 || height < 720 {
            return data
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let compressed = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            compressed,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let jpegOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.75,
        ]
        CGImageDestinationAddImage(destination, cgImage, jpegOptions as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return compressed as Data
    }
}
