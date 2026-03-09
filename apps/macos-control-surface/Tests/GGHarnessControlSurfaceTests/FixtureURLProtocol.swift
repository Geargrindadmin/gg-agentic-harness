import Foundation

final class FixtureURLProtocol: URLProtocol {
    static var handlers: [String: (Int, Data)] = [:]

    private static func routeKey(for url: URL) -> String {
        let host = url.host ?? "fixture-control-plane"
        return host + url.path
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        guard let host = url.host else { return false }
        return host.hasPrefix("fixture-")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let client,
            let handler = Self.handlers[Self.routeKey(for: url)] ?? Self.handlers[url.path]
        else {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://fixture-control-plane")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"error\":\"not found\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let (statusCode, data) = handler
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
