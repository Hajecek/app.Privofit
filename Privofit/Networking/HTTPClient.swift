import Foundation
import OSLog

struct Endpoint<Response: Sendable>: Sendable {
    enum Method: String, Sendable { case get = "GET", post = "POST", delete = "DELETE" }
    let path: String
    let method: Method
    var body: Data? = nil
    var headers: [String: String] = [:]
    // Only confirmed read operations may be retried after refreshing a session.
    var retryAfterRefresh: Bool = false
    let decode: @Sendable (Data) throws -> Response
}
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor HTTPClient {
    private let logger = Logger(subsystem: "cz.privofit.app", category: "network")
    private let baseURL: URL?
    private let session: URLSession
    init(baseURL: URL?, session: URLSession? = nil) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    func send<T>(_ endpoint: Endpoint<T>, bearer: String? = nil) async throws -> T {
        guard let baseURL, Configuration.isAllowedAPIBase(baseURL) else { throw AppFailure.notConfigured("HTTPS API_BASE_URL") }
        guard !endpoint.path.contains("://"), !endpoint.path.hasPrefix("//"),
              !endpoint.path.contains(".."), let url = URL(string: endpoint.path, relativeTo: baseURL)?.absoluteURL,
              Configuration.isAllowedAPIBase(url), url.host == baseURL.host, url.port == baseURL.port else { throw AppFailure.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue; request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        endpoint.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .cannotConnectToHost || error.code == .networkConnectionLost { throw AppFailure.offline }
        catch let error as URLError where error.code == .timedOut { throw AppFailure.timeout }
        catch { throw AppFailure.unavailable }
        guard let http = response as? HTTPURLResponse else { throw AppFailure.invalidResponse }
        logger.debug("HTTP status: \(http.statusCode, privacy: .public)")
        switch http.statusCode {
        case 200..<300: return try endpoint.decode(data)
        case 401: throw AppFailure.unauthorized
        case 403: throw AppFailure.forbidden
        case 400, 404, 409, 422, 500, 502, 503: throw Self.rejected(from: data) ?? AppFailure.http(http.statusCode)
        default: throw AppFailure.http(http.statusCode)
        }
    }
    private static func rejected(from data: Data) -> AppFailure? {
        struct Payload: Decodable { var message: String? }
        guard let message = try? JSONDecoder().decode(Payload.self, from: data).message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...180).contains(trimmed.count) else { return nil }
        return .rejected(trimmed)
    }
}
