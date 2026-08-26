import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedConnection: RemoteConnection?
    @State private var showingDisconnect = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    controls
                    Button {
                        selectedConnection = model.connection
                    } label: {
                        HStack {
                            Label("打开完整 DeepSeek Harness", systemImage: "terminal.fill")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.status?.isReady != true)
                    .accessibilityIdentifier("openHarness")

                    if let message = model.message {
                        Label(message, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(model.connection?.name ?? "DSH Mobile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        Button("断开并重新配对", systemImage: "qrcode", role: .destructive) { showingDisconnect = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .confirmationDialog("断开这台电脑？", isPresented: $showingDisconnect, titleVisibility: .visible) {
                Button("断开并删除配对", role: .destructive) { model.disconnect() }
            }
            .fullScreenCover(item: $selectedConnection) { connection in
                HarnessWebView(connection: connection)
            }
            .task {
                while !Task.isCancelled, model.connection != nil {
                    await model.refresh()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .refreshable { await model.refresh() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: statusColor.opacity(0.5), radius: 7)
                Text(model.status?.label ?? (model.isRefreshing ? "正在连接…" : "电脑离线"))
                    .font(.title2.bold())
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small) }
            }
            Text(model.status?.detail ?? model.connection?.baseURL.host ?? "")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            actionButton("启动", icon: "play.fill", action: .start, enabled: model.status?.state == "stopped" || model.status?.state == "failed")
            actionButton("重启", icon: "arrow.clockwise", action: .restart, enabled: model.status?.canControl == true)
            actionButton("停止", icon: "stop.fill", action: .stop, enabled: model.status?.canControl == true, destructive: true)
        }
    }

    private func actionButton(_ title: String, icon: String, action: RemoteClient.Action, enabled: Bool, destructive: Bool = false) -> some View {
        Button { Task { await model.perform(action) } } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(.bordered)
        .tint(destructive ? .red : .blue)
        .disabled(!enabled)
        .accessibilityIdentifier("action.\(action.rawValue)")
    }

    private var statusColor: Color {
        switch model.status?.state {
        case "running", "externalRunning": return .green
        case "starting", "stopping": return .orange
        case "failed": return .red
        default: return .gray
        }
    }
}
