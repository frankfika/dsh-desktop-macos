import SwiftUI

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingScanner = false
    @State private var manualURL = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.09), Color(red: 0.07, green: 0.14, blue: 0.23)], startPoint: .bottomLeading, endPoint: .topTrailing)
                    .ignoresSafeArea()
                VStack(spacing: 28) {
                    Spacer()
                    Image(systemName: "desktopcomputer.and.iphone")
                        .font(.system(size: 62, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                    VStack(spacing: 10) {
                        Text("连接 DSH Desktop").font(.largeTitle.bold())
                        Text("在电脑端点击「手机」，然后扫描配对二维码。")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        showingScanner = true
                    } label: {
                        Label("扫描电脑二维码", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("scanPairingCode")

                    VStack(spacing: 10) {
                        TextField("或粘贴配对链接", text: $manualURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                        Button("连接") {
                            guard let url = URL(string: manualURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                                model.message = "配对链接格式不正确"
                                return
                            }
                            model.acceptPairingURL(url)
                        }
                        .disabled(manualURL.isEmpty)
                    }
                    Spacer()
                    Text("配对密钥只保存在这台 iPhone 的钥匙串中")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
            }
            .sheet(isPresented: $showingScanner) {
                ScannerView { value in
                    showingScanner = false
                    if let url = URL(string: value) { model.acceptPairingURL(url) }
                }
            }
        }
    }
}

