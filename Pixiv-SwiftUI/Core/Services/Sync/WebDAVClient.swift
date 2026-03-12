import Foundation

actor WebDAVClient {
    private let credentials: WebDAVSyncCredentials
    private let session: URLSession
    private let lastModifiedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()

    init(credentials: WebDAVSyncCredentials) {
        self.credentials = credentials

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func testConnection(ownerId: String) async throws -> [WebDAVRemoteItem] {
        try await ensureAccountDirectoryExists(ownerId: ownerId)
        return try await listItems(ownerId: ownerId)
    }

    func listItems(ownerId: String) async throws -> [WebDAVRemoteItem] {
        let directoryURL = try remoteDirectoryURL(ownerId: ownerId)
                let body = Data(
                        [
                                "<?xml version=\"1.0\" encoding=\"utf-8\" ?>",
                                "<d:propfind xmlns:d=\"DAV:\">",
                                "  <d:prop>",
                                "    <d:getlastmodified />",
                                "    <d:getcontentlength />",
                                "    <d:getetag />",
                                "    <d:resourcetype />",
                                "  </d:prop>",
                                "</d:propfind>",
                        ]
                        .joined(separator: "\n")
                        .utf8
                )

        let (data, _) = try await request(
            url: directoryURL,
            method: "PROPFIND",
            headers: [
                "Depth": "1",
                "Content-Type": "application/xml; charset=utf-8",
            ],
            body: body,
            acceptableStatusCodes: [207]
        )

        let items = try await parseMultiStatus(data: data)
        let directoryName = directoryURL.lastPathComponent
        return items.filter { item in
            item.fileName != directoryName && !item.fileName.isEmpty
        }
    }

    func upload(_ data: Data, fileName: String, ownerId: String) async throws {
        try await ensureAccountDirectoryExists(ownerId: ownerId)
        let fileURL = try remoteFileURL(fileName: fileName, ownerId: ownerId)
        _ = try await request(
            url: fileURL,
            method: "PUT",
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data,
            acceptableStatusCodes: [200, 201, 204]
        )
    }

    func download(fileName: String, ownerId: String) async throws -> Data {
        let fileURL = try remoteFileURL(fileName: fileName, ownerId: ownerId)
        do {
            let (data, _) = try await request(url: fileURL, method: "GET", acceptableStatusCodes: [200])
            return data
        } catch let error as WebDAVSyncError {
            if case .httpStatus(let statusCode) = error, statusCode == 404 {
                throw WebDAVSyncError.remoteFileNotFound(fileName)
            }
            throw error
        }
    }

    private func ensureAccountDirectoryExists(ownerId: String) async throws {
        let components = remotePathComponents(ownerId: ownerId)
        var currentURL = credentials.serverURL

        for component in components {
            currentURL.appendPathComponent(component, isDirectory: true)
            do {
                _ = try await request(url: currentURL, method: "MKCOL", acceptableStatusCodes: [201])
            } catch let error as WebDAVSyncError {
                switch error {
                case .httpStatus(let statusCode) where statusCode == 405 || statusCode == 301:
                    continue
                default:
                    throw error
                }
            }
        }
    }

    private func request(
        url: URL,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        acceptableStatusCodes: Set<Int>
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(authorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("Pixiv-SwiftUI/1.0", forHTTPHeaderField: "User-Agent")

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVSyncError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw WebDAVSyncError.authenticationFailed
        }

        guard acceptableStatusCodes.contains(httpResponse.statusCode) else {
            throw WebDAVSyncError.httpStatus(httpResponse.statusCode)
        }

        return (data, httpResponse)
    }

    private func authorizationHeader() -> String {
        let raw = "\(credentials.username):\(credentials.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func remotePathComponents(ownerId: String) -> [String] {
        let directoryComponents = credentials.remoteDirectory
            .split(separator: "/")
            .map(String.init)
        return directoryComponents + [ownerId]
    }

    private func remoteDirectoryURL(ownerId: String) throws -> URL {
        var url = credentials.serverURL
        for component in remotePathComponents(ownerId: ownerId) {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url
    }

    private func remoteFileURL(fileName: String, ownerId: String) throws -> URL {
        var url = try remoteDirectoryURL(ownerId: ownerId)
        url.appendPathComponent(fileName, isDirectory: false)
        return url
    }

    private func parseMultiStatus(data: Data) async throws -> [WebDAVRemoteItem] {
        try await MainActor.run {
            let parserDelegate = WebDAVMultiStatusParser(lastModifiedFormatter: lastModifiedFormatter)
            let parser = XMLParser(data: data)
            parser.delegate = parserDelegate

            guard parser.parse() else {
                throw WebDAVSyncError.xmlParsingFailed
            }

            return parserDelegate.items
        }
    }
}

private final class WebDAVMultiStatusParser: NSObject, XMLParserDelegate {
    private struct CurrentResponse {
        var href: String = ""
        var etag: String?
        var lastModified: Date?
        var contentLength: Int64?
        var isDirectory = false
    }

    private enum Element: Equatable {
        case response
        case href
        case getETag
        case getLastModified
        case getContentLength
        case resourceType
        case collection
        case other

        init(name: String) {
            let normalizedName = name.split(separator: ":").last.map(String.init) ?? name
            switch normalizedName.lowercased() {
            case "response":
                self = .response
            case "href":
                self = .href
            case "getetag":
                self = .getETag
            case "getlastmodified":
                self = .getLastModified
            case "getcontentlength":
                self = .getContentLength
            case "resourcetype":
                self = .resourceType
            case "collection":
                self = .collection
            default:
                self = .other
            }
        }
    }

    private let lastModifiedFormatter: DateFormatter
    private var currentResponse: CurrentResponse?
    private var currentValue = ""

    var items: [WebDAVRemoteItem] = []

    init(lastModifiedFormatter: DateFormatter) {
        self.lastModifiedFormatter = lastModifiedFormatter
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = Element(name: elementName)
        currentValue = ""

        if element == .response {
            currentResponse = CurrentResponse()
        } else if element == .collection {
            currentResponse?.isDirectory = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard var currentResponse else {
            currentValue = ""
            return
        }

        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Element(name: elementName) {
        case .href:
            currentResponse.href = value.removingPercentEncoding ?? value
            self.currentResponse = currentResponse
        case .getETag:
            currentResponse.etag = value.isEmpty ? nil : value
            self.currentResponse = currentResponse
        case .getLastModified:
            currentResponse.lastModified = value.isEmpty ? nil : lastModifiedFormatter.date(from: value)
            self.currentResponse = currentResponse
        case .getContentLength:
            currentResponse.contentLength = Int64(value)
            self.currentResponse = currentResponse
        case .response:
            let normalizedHref = currentResponse.href.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let fileName = (normalizedHref as NSString).lastPathComponent
            items.append(WebDAVRemoteItem(
                href: currentResponse.href,
                fileName: fileName,
                isDirectory: currentResponse.isDirectory,
                etag: currentResponse.etag,
                lastModified: currentResponse.lastModified,
                contentLength: currentResponse.contentLength
            ))
            self.currentResponse = nil
        default:
            break
        }

        currentValue = ""
    }
}
