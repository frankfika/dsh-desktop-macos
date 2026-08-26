import Foundation

struct RemoteConnection: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let baseURL: URL
    let token: String

    init(name: String = "我的电脑", baseURL: URL, token: String) {
        self.id = UUID()
        self.name = name
        self.baseURL = baseURL
        self.token = token
    }

    var dashboardURL: URL { baseURL.appendingPathComponent("__remote", isDirectory: true) }
    var statusURL: URL {
        baseURL.appendingPathComponent("__remote", isDirectory: true)
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("status")
    }
    var actionURL: URL {
        baseURL.appendingPathComponent("__remote", isDirectory: true)
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("action")
    }

    static func from(pairingURL: URL) -> RemoteConnection? {
        guard pairingURL.scheme == "http" || pairingURL.scheme == "https",
              let host = pairingURL.host,
              pairingURL.path == "/__remote/pair",
              let components = URLComponents(url: pairingURL, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              token.count >= 16 else { return nil }
        var base = URLComponents()
        base.scheme = pairingURL.scheme
        base.host = host
        base.port = pairingURL.port
        base.path = "/"
        guard let baseURL = base.url else { return nil }
        return RemoteConnection(baseURL: baseURL, token: token)
    }
}

struct RemoteStatus: Decodable, Equatable {
    let state: String
    let label: String
    let detail: String?
    let controllable: Bool?

    var isReady: Bool { state == "running" || state == "externalRunning" }
    var canControl: Bool { controllable ?? false }
}
