import Foundation
import os.log
import Kingfisher
#if os(iOS)
import UIKit
import Photos
#else
import AppKit
#endif

enum ImageSaverError: LocalizedError {
    case permissionDenied
    case invalidData
    case writeFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有相册访问权限，请在设置中允许访问"
        case .invalidData:
            return "图片数据无效"
        case .writeFailed(let message):
            return "保存失败: \(message)"
        case .downloadFailed(let message):
            return "下载失败: \(message)"
        }
    }
}

struct ImageSaver {

    #if os(iOS)
    private static let photoLibraryQueue = DispatchQueue(label: "com.pixiv.photo-library.save", qos: .userInitiated)
    #endif

    static func saveToPhotosAlbum(data: Data, fileExtension: String = "jpg") async throws {
        #if os(iOS)
        let normalizedExtension = normalizedPhotoFileExtension(fileExtension)
        Logger.download.debug("开始保存到相册，数据大小: \(data.count) bytes, 扩展名: \(normalizedExtension, privacy: .public)")

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        Logger.download.debug("相册权限状态: \(status.rawValue)")

        switch status {
        case .authorized, .limited:
            break
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            Logger.download.debug("请求权限后状态: \(newStatus.rawValue)")
            if newStatus != .authorized && newStatus != .limited {
                throw ImageSaverError.permissionDenied
            }
        case .denied, .restricted:
            throw ImageSaverError.permissionDenied
        @unknown default:
            throw ImageSaverError.permissionDenied
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(normalizedExtension)

        do {
            try data.write(to: tempURL, options: .atomic)
            defer {
                try? FileManager.default.removeItem(at: tempURL)
            }

            try await saveToPhotosAlbum(fileURL: tempURL)
        } catch let error as ImageSaverError {
            throw error
        } catch {
            throw ImageSaverError.writeFailed(error.localizedDescription)
        }
        Logger.download.debug("保存到相册成功")
        #else
        throw ImageSaverError.permissionDenied
        #endif
    }

    static func saveToFile(data: Data, url: URL, filename: String? = nil) async throws {
        let saveURL: URL
        if let customURL = url as URL?, !customURL.hasDirectoryPath {
            saveURL = customURL
        } else {
            let finalFilename = filename ?? "image_\(Date().timeIntervalSince1970).jpg"
            saveURL = url.appendingPathComponent(finalFilename)
        }

        try data.write(to: saveURL)
    }

    static func createZip(from files: [URL], outputURL: URL) async throws {
        #if os(macOS)
        try? FileManager.default.removeItem(at: outputURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", outputURL.path] + files.map { $0.path }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ImageSaverError.writeFailed("zip 进程返回错误")
        }
        #else
        throw ImageSaverError.writeFailed("ZIP 创建仅在 macOS 支持")
        #endif
    }

    static func getCachedImageData(for urlString: String) async -> Data? {
        let cacheKey = urlString
        
        // 1. 尝试从磁盘读取原始数据
        // Kingfisher 的 isCached(forKey:) 是同步的
        if ImageCache.default.isCached(forKey: cacheKey) {
            return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                // 使用 retrieveImage 从磁盘获取
                ImageCache.default.retrieveImage(forKey: cacheKey, options: [.onlyFromCache]) { result in
                    switch result {
                    case .success(let cacheResult):
                        // 尝试从磁盘缓存路径直接读取二进制数据
                        let diskCachePath = ImageCache.default.cachePath(forKey: cacheKey)
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: diskCachePath)) {
                            continuation.resume(returning: data)
                        } else {
                            // 如果直接读取失败，返回解压缩后的图片 data
                            if let image = cacheResult.image {
                                #if os(iOS)
                                continuation.resume(returning: image.pngData())
                                #else
                                continuation.resume(returning: image.tiffRepresentation)
                                #endif
                            } else {
                                continuation.resume(returning: nil)
                            }
                        }
                    case .failure:
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        
        return nil
    }

    static func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            Logger.download.error("无效的 URL: \(urlString, privacy: .public)")
            throw ImageSaverError.downloadFailed("无效的 URL")
        }

        Logger.download.debug("开始下载: \(url.lastPathComponent, privacy: .public)")

        var headers: [String: String] = [:]
        if let modifiedRequest = PixivImageLoader.shared.modified(for: URLRequest(url: url)) {
            headers = modifiedRequest.allHTTPHeaderFields ?? [:]
        }

        let (tempURL, response) = try await NetworkClient.shared.download(from: url, headers: headers)
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        Logger.download.debug("下载完成，数据大小: \(data.count) bytes")

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.download.error("错误: 无效的 HTTP 响应")
            throw ImageSaverError.downloadFailed("无效的 HTTP 响应")
        }

        Logger.download.debug("HTTP 状态码: \(httpResponse.statusCode), Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "nil")")

        guard (200...299).contains(httpResponse.statusCode) else {
            Logger.download.error("错误: HTTP 状态码异常 \(httpResponse.statusCode)")
            throw ImageSaverError.downloadFailed("HTTP 错误: \(httpResponse.statusCode)")
        }

        guard !data.isEmpty else {
            Logger.download.error("错误: 返回数据为空")
            throw ImageSaverError.downloadFailed("返回数据为空")
        }

        return data
    }

    static func sanitizeFilename(_ filename: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return filename
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .prefix(200)
            .description
    }

    #if os(iOS)
    private static func saveToPhotosAlbum(fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            photoLibraryQueue.async {
                do {
                    try autoreleasepool {
                        try PHPhotoLibrary.shared().performChangesAndWait {
                            let request = PHAssetCreationRequest.forAsset()
                            let options = PHAssetResourceCreationOptions()
                            options.shouldMoveFile = true
                            request.addResource(with: .photo, fileURL: fileURL, options: options)
                        }
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: ImageSaverError.writeFailed(error.localizedDescription))
                }
            }
        }
    }

    private static func normalizedPhotoFileExtension(_ fileExtension: String) -> String {
        let trimmedExtension = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !trimmedExtension.isEmpty else {
            return "jpg"
        }

        return trimmedExtension == "jpeg" ? "jpg" : trimmedExtension
    }
    #endif

    static func convert(data: Data, toExtension: String) -> Data {
        let ext = toExtension.lowercased()
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return data }
        if ext == "png" {
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
        } else if ext == "jpg" || ext == "jpeg" {
            if let tiffData = nsImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                return jpegData
            }
        }
        #else
        guard let uiImage = UIImage(data: data) else { return data }
        if ext == "png" {
            return uiImage.pngData() ?? data
        } else if ext == "jpg" || ext == "jpeg" {
            return uiImage.jpegData(compressionQuality: 0.9) ?? data
        }
        #endif
        return data
    }
}
