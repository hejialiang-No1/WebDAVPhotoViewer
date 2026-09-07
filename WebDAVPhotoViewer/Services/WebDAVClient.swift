import Foundation
import CommonCrypto

// MARK: - 错误类型
enum WebDAVError: LocalizedError {
    case invalidResponse
    case authFailed
    case http(Int)
    case invalidImage
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效的服务器响应"
        case .authFailed:      return "登录失败：用户名或密码错误"
        case .http(let code):  return "服务器返回错误（HTTP \(code)）"
        case .invalidImage:    return "无法解码该图片"
        case .network(let e):  return "网络错误：\(e.localizedDescription)"
        }
    }
}

// MARK: - 加解密辅助
extension String {
    var sha256: String {
        let data = Data(utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress!, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    var md5: String {
        let data = Data(utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress!, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Digest 挑战
private struct DigestChallenge {
    let realm: String
    let nonce: String
    let opaque: String
    let qop: String?
    let algorithm: String
}

// MARK: - WebDAV 客户端
final class WebDAVClient {
    let baseURL: URL
    private let username: String
    private let password: String
    private let session: URLSession
    private var challenge: DigestChallenge?
    private let allowInsecure: Bool

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    init(baseURL: URL, username: String, password: String, allowInsecure: Bool = true) {
        var urlString = baseURL.absoluteString
        if !urlString.hasSuffix("/") { urlString += "/" }
        self.baseURL = URL(string: urlString) ?? baseURL
        self.username = username
        self.password = password
        self.allowInsecure = allowInsecure

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = SessionDelegate(allowInsecure: allowInsecure)
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: 公开接口
    func listFiles(at path: String) async throws -> [WebDAVItem] {
        let url = resolveURL(path)
        let body = Self.propfindBody.data(using: .utf8)
        let (data, _) = try await request(url, method: "PROPFIND", body: body,
                                          extraHeaders: ["Depth": "1",
                                                         "Content-Type": "application/xml; charset=utf-8"])
        return WebDAVPropFindParser(baseURL: baseURL, dateFormatter: dateFormatter).parse(data)
    }

    func downloadData(at absoluteURLString: String) async throws -> Data {
        guard let url = URL(string: absoluteURLString) else { throw WebDAVError.invalidResponse }
        let (data, _) = try await request(url, method: "GET")
        return data
    }

    /// 递归扫描：从指定路径出发，逐层 PROPFIND 收集所有照片（自动识别全部图片格式）
    /// - 限制最大深度与最大数量，避免超大目录树耗尽资源
    func scanAllPhotos(at path: String, maxDepth: Int = 8, maxItems: Int = 3000) async throws -> [WebDAVItem] {
        var result: [WebDAVItem] = []
        var pending = [path]
        var depth = 0
        while !pending.isEmpty, depth <= maxDepth, result.count < maxItems {
            let batch = pending
            pending = []
            for dir in batch {
                let listing = try await listFiles(at: dir)
                let selfURL = resolveURL(dir).absoluteString.trimmingCharacters(in: ["/"])
                for item in listing {
                    if item.isDirectory {
                        // 跳过目录自身，避免死循环
                        if item.id.trimmingCharacters(in: ["/"]) == selfURL { continue }
                        pending.append(item.id)
                    } else if item.isImage {
                        result.append(item)
                        if result.count >= maxItems { break }
                    }
                }
            }
            depth += 1
        }
        return result
    }

    // MARK: 内部请求（含 Basic / Digest 握手）
    private func request(_ url: URL, method: String, body: Data? = nil,
                         extraHeaders: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        for _ in 0..<2 {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.httpBody = body
            for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
            addAuthHeader(to: &req, method: method, path: url.path)

            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw WebDAVError.invalidResponse }

            if http.statusCode == 401 {
                if let ch = parseDigestChallenge(http) {
                    self.challenge = ch
                    continue
                }
                throw WebDAVError.authFailed
            }
            guard (200...299).contains(http.statusCode) else { throw WebDAVError.http(http.statusCode) }
            return (data, http)
        }
        throw WebDAVError.authFailed
    }

    private func resolveURL(_ path: String) -> URL {
        if let u = URL(string: path), u.scheme != nil { return u }
        // 绝对路径引用（以 / 开头）：以 baseURL 的 scheme+host 为根拼接，
        // 避免丢掉 baseURL 自身的挂载路径（如 /dav/）
        if path.hasPrefix("/"), let host = baseURL.host {
            let scheme = baseURL.scheme ?? "https"
            return URL(string: "\(scheme)://\(host)\(path)") ?? baseURL
        }
        return baseURL.appendingPathComponent(path)
    }

    private func addAuthHeader(to req: inout URLRequest, method: String, path: String) {
        if let ch = challenge {
            req.setValue(digestHeader(method: method, path: path, challenge: ch), forHTTPHeaderField: "Authorization")
        } else {
            let cred = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
    }

    private func parseDigestChallenge(_ response: HTTPURLResponse) -> DigestChallenge? {
        let header = response.allHeaderFields
            .first(where: { ($0.key as? String)?.lowercased() == "www-authenticate" })?
            .value as? String
        guard let header = header, header.hasPrefix("Digest") else { return nil }
        var realm = "", nonce = "", opaque = "", qop: String? = nil, algorithm = "MD5"
        let pattern = #"(\w+)=(?:"([^"]*)"|([^,]*))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(header.startIndex..., in: header)
        regex.enumerateMatches(in: header, range: nsrange) { match, _, _ in
            guard let match = match else { return }
            let key = (header as NSString).substring(with: match.range(at: 1))
            let val = (header as NSString).substring(with: match.range(at: 2))
            switch key {
            case "realm":     realm = val
            case "nonce":     nonce = val
            case "opaque":    opaque = val
            case "qop":       qop = val
            case "algorithm": algorithm = val
            default: break
            }
        }
        guard !nonce.isEmpty else { return nil }
        return DigestChallenge(realm: realm, nonce: nonce, opaque: opaque, qop: qop, algorithm: algorithm)
    }

    private func digestHeader(method: String, path: String, challenge ch: DigestChallenge) -> String {
        let ha1 = "\(username):\(ch.realm):\(password)".md5
        let ha2 = "\(method):\(path)".md5
        let cnonce = String(format: "%08x", Int.random(in: 0..<0xffffffff))
        let nc = "00000001"
        let qop = ch.qop ?? "auth"
        let response: String
        if ch.qop != nil {
            response = "\(ha1):\(ch.nonce):\(nc):\(cnonce):\(qop):\(ha2)".md5
        } else {
            response = "\(ha1):\(ch.nonce):\(ha2)".md5
        }
        var parts = [
            "username=\"\(username)\"",
            "realm=\"\(ch.realm)\"",
            "nonce=\"\(ch.nonce)\"",
            "uri=\"\(path)\"",
            "response=\"\(response)\""
        ]
        if ch.qop != nil {
            parts.append("qop=\(qop)")
            parts.append("nc=\(nc)")
            parts.append("cnonce=\"\(cnonce)\"")
        }
        if !ch.opaque.isEmpty { parts.append("opaque=\"\(ch.opaque)\"") }
        return "Digest " + parts.joined(separator: ", ")
    }

    private static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
      <D:prop>
        <D:resourcetype/>
        <D:getcontentlength/>
        <D:getcontenttype/>
        <D:getlastmodified/>
        <D:displayname/>
      </D:prop>
    </D:propfind>
    """
}

// MARK: - 自签名证书放行（个人 NAS / 自建服务常用）
private final class SessionDelegate: NSObject, URLSessionDelegate {
    let allowInsecure: Bool
    init(allowInsecure: Bool) { self.allowInsecure = allowInsecure }

    func urlSession(_ session: URLSession,
                   didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           allowInsecure,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - PROPFIND XML 解析
private final class WebDAVPropFindParser: NSObject, XMLParserDelegate {
    private let baseURL: URL
    private let dateFormatter: DateFormatter
    private var items: [WebDAVItem] = []

    private var currentElement = ""
    private var currentValue = ""          // 累计一个元素内的文本（XMLParser 可能分片回调）
    private var inResponse = false
    private var currentHref = ""
    private var isCollection = false
    private var contentLength: Int64 = 0
    private var contentType: String?
    private var lastModified: Date?
    private var displayName: String?

    init(baseURL: URL, dateFormatter: DateFormatter) {
        self.baseURL = baseURL
        self.dateFormatter = dateFormatter
    }

    func parse(_ data: Data) -> [WebDAVItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    /// 去掉命名空间前缀：D:response / d:href / response 都归一为本地名 response / href
    private func localName(_ elementName: String) -> String {
        elementName.components(separatedBy: ":").last ?? elementName
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = localName(elementName).lowercased()
        currentValue = ""
        if currentElement == "response" {
            inResponse = true
            currentHref = ""
            isCollection = false
            contentLength = 0
            contentType = nil
            lastModified = nil
            displayName = nil
        }
        if currentElement == "collection" { isCollection = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let el = localName(elementName).lowercased()
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "href":             currentHref = value
        case "getcontentlength": if !value.isEmpty { contentLength = Int64(value) ?? 0 }
        case "getcontenttype":   contentType = value.isEmpty ? nil : value
        case "getlastmodified":  lastModified = dateFormatter.date(from: value)
        case "displayname":      if !value.isEmpty { displayName = (displayName ?? "") + value }
        default: break
        }
        if el == "response" {
            inResponse = false
            if let item = buildItem() { items.append(item) }
        }
        currentElement = ""
        currentValue = ""
    }

    private func buildItem() -> WebDAVItem? {
        guard !currentHref.isEmpty else { return nil }
        let href = currentHref
        // 保留百分号编码的 URL 作为 id，确保 URL(string:) 始终可解析
        let absolute = URL(string: href, relativeTo: baseURL)?.absoluteString ?? href
        // 名称单独解码，便于显示中文 / 空格路径
        let decodedHref = href.removingPercentEncoding ?? href
        let rawName = displayName?.nilIfEmpty
            ?? (decodedHref as NSString).lastPathComponent.nilIfEmpty
            ?? href
        let name = rawName.removingPercentEncoding ?? rawName
        let estimated: CGFloat = isCollection ? 120 : 220
        return WebDAVItem(id: absolute, name: name, isDirectory: isCollection,
                          contentType: contentType, size: contentLength,
                          modified: lastModified, estimatedHeight: estimated)
    }
}
