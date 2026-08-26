import SwiftUI
import WebKit

struct HarnessWebView: View {
    let connection: RemoteConnection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AuthenticatedWebView(connection: connection)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("DeepSeek Harness")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}

private struct AuthenticatedWebView: UIViewRepresentable {
    let connection: RemoteConnection

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        guard let host = connection.baseURL.host,
              let cookie = HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: "dsh_remote_session",
                .value: connection.token,
                .secure: connection.baseURL.scheme == "https" ? "TRUE" : "FALSE",
                .expires: Date().addingTimeInterval(30 * 24 * 60 * 60),
              ]) else { return webView }
        configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
            webView.load(URLRequest(url: connection.baseURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

