import Foundation

struct RemoteClient {
    let connection: RemoteConnection

    private var cookie: String { "dsh_remote_session=\(connection.token)" }

    func status() async throws -> RemoteStatus {
        var request = URLRequest(url: connection.statusURL)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(RemoteStatus.self, from: data)
    }

    func send(_ action: Action) async throws {
        var request = URLRequest(url: connection.actionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.httpBody = try JSONEncoder().encode(["action": action.rawValue])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RemoteError.rejected
        }
    }

    enum Action: String { case start, stop, restart }
    enum RemoteError: LocalizedError {
        case rejected
        var errorDescription: String? { "电脑拒绝了请求，请重新配对" }
    }
}

