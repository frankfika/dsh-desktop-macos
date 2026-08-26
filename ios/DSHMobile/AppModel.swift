import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var connection: RemoteConnection?
    @Published private(set) var status: RemoteStatus?
    @Published private(set) var isRefreshing = false
    @Published var message: String?

    init() {
        connection = KeychainStore.load()
    }

    func acceptPairingURL(_ url: URL) {
        guard let candidate = RemoteConnection.from(pairingURL: url) else {
            message = "这不是有效的 DSH Desktop 配对二维码"
            return
        }
        do {
            try KeychainStore.save(candidate)
            connection = candidate
            status = nil
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func disconnect() {
        KeychainStore.remove()
        connection = nil
        status = nil
        message = nil
    }

    func refresh() async {
        guard let connection else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            status = try await RemoteClient(connection: connection).status()
            message = nil
        } catch is CancellationError {
            return
        } catch {
            status = nil
            message = "连接不到电脑。请确认 DSH Desktop 正在运行，并且手机与电脑网络互通。"
        }
    }

    func perform(_ action: RemoteClient.Action) async {
        guard let connection else { return }
        do {
            try await RemoteClient(connection: connection).send(action)
            try? await Task.sleep(for: .milliseconds(700))
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
