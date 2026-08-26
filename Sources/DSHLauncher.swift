import SwiftUI
import AppKit
@preconcurrency import WebKit
import ServiceManagement
import Darwin
import CoreImage.CIFilterBuiltins

// MARK: - 小工具函数

/// 执行一条外部命令并返回合并后的 stdout/stderr
func shellOut(_ path: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 查询监听某个 TCP 端口的进程 PID
func listeningPid(port: Int) -> Int32? {
    guard let out = shellOut("/usr/sbin/lsof", ["-tiTCP:\(port)", "-sTCP:LISTEN"]) else { return nil }
    guard let first = out.split(separator: "\n").first, let pid = Int32(first) else { return nil }
    return pid
}

/// 查询进程的命令行
func commandOf(pid: Int32) -> String {
    shellOut("/bin/ps", ["-p", "\(pid)", "-o", "command="]) ?? ""
}

/// 对服务做一次真实 HTTP 健康检查：收到任何 HTTP 响应（2xx/3xx/4xx/5xx）都说明服务活着，
/// 而不仅仅是 TCP 端口连通。连接被拒 / 超时 / 挂死无响应 → 返回 false。
/// 用于区分「健康的 dsh 实例」与「残留的僵尸进程（占着端口但不响应）」。
func isHttpAlive(_ host: String, _ port: Int, timeout: TimeInterval = 2.0) -> Bool {
    let name = host.isEmpty ? "127.0.0.1" : host
    guard let url = URL(string: "http://\(name):\(port)/") else { return false }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let sem = DispatchSemaphore(value: 0)
    var alive = false
    let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
        if let r = resp as? HTTPURLResponse {
            alive = (100...599).contains(r.statusCode)
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + timeout + 1.0)
    task.cancel()
    return alive
}

/// 常见 dsh 可执行文件候选位置（按优先级）
func dshCandidates() -> [String] {
    var list: [String] = []
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    // 稳定安装位置（不受 npm/npx 缓存清理影响）
    let stable = home + "/.dsh/app/node_modules/.bin/dsh"
    if FileManager.default.isExecutableFile(atPath: stable) {
        list.append(stable)
    }
    let npxRoot = home + "/.npm/_npx"
    if let dirs = try? FileManager.default.contentsOfDirectory(atPath: npxRoot) {
        var bins: [(path: String, date: Date)] = []
        for d in dirs {
            let b = npxRoot + "/" + d + "/node_modules/.bin/dsh"
            guard FileManager.default.isExecutableFile(atPath: b) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: b)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            bins.append((b, date))
        }
        list += bins.sorted { $0.date > $1.date }.map { $0.path }
    }
    list += [
        "/opt/homebrew/bin/dsh",
        "/usr/local/bin/dsh",
        home + "/.npm-global/bin/dsh",
        "/usr/bin/dsh",
        "/bin/dsh",
    ]
    return list
}

/// 解析 dsh 路径：优先用户保存的，其次自动探测
func resolveDshPath() -> String {
    if let stored = UserDefaults.standard.string(forKey: "dshPath"),
       FileManager.default.isExecutableFile(atPath: stored) {
        return stored
    }
    for c in dshCandidates() where FileManager.default.isExecutableFile(atPath: c) {
        UserDefaults.standard.set(c, forKey: "dshPath")
        return c
    }
    return ""
}

/// 解析 dsh 路径背后的真实脚本文件（跟随符号链接，支持相对链接）
func resolvedScriptPath(_ path: String) -> String {
    var current = path
    for _ in 0..<8 { // 防循环链接
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: current) else {
            return current
        }
        if resolved.hasPrefix("/") {
            current = resolved
        } else {
            let dir = (current as NSString).deletingLastPathComponent
            current = dir + "/" + resolved
        }
    }
    return current
}

/// 查找 Node.js 可执行文件，用于直接解释 dsh 脚本（避免 GUI 应用环境 PATH 不完整导致 shebang 找不到 node）
func findNodeExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let staticCandidates: [String] = [
        "/opt/homebrew/bin/node",
        "/usr/local/bin/node",
        home + "/.nvm/versions/node/default/bin/node",
    ]
    for c in staticCandidates where FileManager.default.isExecutableFile(atPath: c) {
        return c
    }
    // 动态扫描 nvm / workbuddy 等版本管理目录
    let versionRoots = [
        home + "/.nvm/versions/node",
        home + "/.workbuddy/binaries/node/versions",
    ]
    for root in versionRoots {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        var nodes: [(path: String, date: Date)] = []
        for v in versions {
            let nodePath = root + "/" + v + "/bin/node"
            guard FileManager.default.isExecutableFile(atPath: nodePath) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: nodePath)
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            nodes.append((nodePath, date))
        }
        if let latest = nodes.sorted(by: { $0.date > $1.date }).first {
            return latest.path
        }
    }
    return nil
}

/// 查找与 Node.js 配套的 npm，用于在用户确认后安装官方 DSH 运行时。
func findNpmExecutable() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var candidates = [
        "/opt/homebrew/bin/npm",
        "/usr/local/bin/npm",
        home + "/.nvm/versions/node/default/bin/npm",
    ]
    if let node = findNodeExecutable() {
        candidates.insert((node as NSString).deletingLastPathComponent + "/npm", at: 0)
    }
    candidates += dynamicNodeBinDirs(home: home).map { $0 + "/npm" }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// 把常见 Node 安装目录加入 PATH，确保 dsh 的 shebang `#!/usr/bin/env node` 能找到解释器
func enrichedEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let nodeDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        home + "/.nvm/versions/node/default/bin",
        home + "/.workbuddy/binaries/node/versions/current/bin",
    ] + dynamicNodeBinDirs(home: home)
    let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
    let additions = nodeDirs.filter { FileManager.default.fileExists(atPath: $0) && !existing.contains($0) }
    if !additions.isEmpty {
        env["PATH"] = (additions + existing).joined(separator: ":")
    }
    return env
}

func dynamicNodeBinDirs(home: String) -> [String] {
    var dirs: [String] = []
    for root in [home + "/.nvm/versions/node", home + "/.workbuddy/binaries/node/versions"] {
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
        for v in versions {
            let binDir = root + "/" + v + "/bin"
            if FileManager.default.fileExists(atPath: binDir + "/node") {
                dirs.append(binDir)
            }
        }
    }
    return dirs
}

/// 优先返回 Wi-Fi/有线网卡的 IPv4 地址，供手机在同一局域网访问。
func localNetworkAddress() -> String? {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(head) }
    var candidates: [(name: String, address: String)] = []
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let item = cursor {
        let flags = Int32(item.pointee.ifa_flags)
        if let addr = item.pointee.ifa_addr,
           addr.pointee.sa_family == UInt8(AF_INET),
           (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                candidates.append((String(cString: item.pointee.ifa_name), String(cString: host)))
            }
        }
        cursor = item.pointee.ifa_next
    }
    return candidates.sorted { lhs, rhs in
        let priority = { (name: String) -> Int in name == "en0" ? 0 : (name.hasPrefix("en") ? 1 : 2) }
        return priority(lhs.name) < priority(rhs.name)
    }.first?.address
}

func makeRemoteToken() -> String {
    (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
}

// MARK: - 状态机

enum DSHState: Equatable {
    case stopped
    case starting
    case running(Int32)
    case externalRunning(Int32)
    case stopping
    case failed(String)

    static func == (l: DSHState, r: DSHState) -> Bool {
        switch (l, r) {
        case (.stopped, .stopped), (.starting, .starting), (.stopping, .stopping):
            return true
        case (.running(let a), .running(let b)):
            return a == b
        case (.externalRunning(let a), .externalRunning(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    /// 端口上有服务在监听（无论是本应用启动的还是外部实例）—— 用于「打开浏览器」等
    var portActive: Bool {
        switch self {
        case .running, .externalRunning, .starting:
            return true
        default:
            return false
        }
    }

    /// 空闲状态（stopped / failed）—— 可以尝试启动
    var canTryStart: Bool {
        switch self {
        case .stopped, .failed:
            return true
        default:
            return false
        }
    }

    /// 服务已就绪，可以嵌入显示 DSH 界面
    var webReady: Bool {
        switch self {
        case .running, .externalRunning:
            return true
        default:
            return false
        }
    }
}

// MARK: - 核心管理器

final class Manager: ObservableObject {
    static let shared = Manager()

    @Published var state: DSHState = .stopped { didSet { updateRemoteStatus() } }
    @Published var logs: String = ""
    @Published var dshPath: String = UserDefaults.standard.string(forKey: "dshPath") ?? resolveDshPath()
    @Published var host: String = UserDefaults.standard.string(forKey: "host") ?? "127.0.0.1"
    @Published var port: Int = {
        let p = UserDefaults.standard.integer(forKey: "port")
        return p == 0 ? 3080 : p
    }()
    @Published var autoStart: Bool = {
        if let v = UserDefaults.standard.object(forKey: "autoStart") as? Bool { return v }
        return true
    }()
    @Published var stopOnQuit: Bool = {
        if let v = UserDefaults.standard.object(forKey: "stopOnQuit") as? Bool { return v }
        return true
    }()
    @Published var cleanupStaleOnStart: Bool = {
        if let v = UserDefaults.standard.object(forKey: "cleanupStaleOnStart") as? Bool { return v }
        return true
    }()
    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @Published var isInstallingRuntime: Bool = false
    @Published var remoteEnabled: Bool = UserDefaults.standard.bool(forKey: "remoteEnabled")
    @Published var remotePort: Int = {
        let value = UserDefaults.standard.integer(forKey: "remotePort")
        return value == 0 ? 3081 : value
    }()
    @Published var remoteRunning: Bool = false
    @Published var remoteToken: String = {
        if let saved = UserDefaults.standard.string(forKey: "remoteToken"), saved.count >= 16 { return saved }
        let token = makeRemoteToken()
        UserDefaults.standard.set(token, forKey: "remoteToken")
        return token
    }()

    private var proc: Process?
    private var installProc: Process?
    private var readyTimer: Timer?
    private var watchTimer: Timer?
    private var remoteCommandTimer: Timer?
    private var logLines: [String] = []
    private var pendingRestart = false
    private var warnedBusy = false
    private var lastHealthCheck: Date?
    private var healthFailStreak = 0
    private var remoteProc: Process?
    private var remoteConfigurationRestart: DispatchWorkItem?
    private var remoteRestartAfterExternalStop = false

    var url: URL {
        URL(string: "http://\(host):\(port)") ?? URL(string: "http://127.0.0.1:3080")!
    }
    var remoteAddress: String { localNetworkAddress() ?? "127.0.0.1" }
    var remotePairingURL: URL? {
        URL(string: "http://\(remoteAddress):\(remotePort)/__remote/pair?token=\(remoteToken)")
    }
    var remoteDashboardURL: URL? { URL(string: "http://\(remoteAddress):\(remotePort)/__remote/") }
    /// 是否由本应用托管了子进程
    var ownsProcess: Bool { proc != nil }
    /// 是否可以点击「启动」
    var canStart: Bool {
        if case .stopped = state { return !dshPath.isEmpty }
        return false
    }

    private init() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refreshExternal()
        }
        remoteCommandTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.consumeRemoteCommand()
            self?.updateRemoteStatus()
        }
        if remoteEnabled { DispatchQueue.main.async { [weak self] in self?.startRemoteAccess() } }
    }

    // MARK: 持久化

    func persist() {
        let d = UserDefaults.standard
        d.set(dshPath, forKey: "dshPath")
        d.set(host, forKey: "host")
        d.set(port, forKey: "port")
        d.set(autoStart, forKey: "autoStart")
        d.set(stopOnQuit, forKey: "stopOnQuit")
        d.set(cleanupStaleOnStart, forKey: "cleanupStaleOnStart")
        d.set(remoteEnabled, forKey: "remoteEnabled")
        d.set(remotePort, forKey: "remotePort")
        d.set(remoteToken, forKey: "remoteToken")
    }

    // MARK: 手机远程控制

    private var remoteDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DSH Desktop/Remote", isDirectory: true)
    }

    func setRemoteEnabled(_ enabled: Bool) {
        remoteEnabled = enabled
        persist()
        if !enabled {
            remoteConfigurationRestart?.cancel()
            remoteConfigurationRestart = nil
        }
        enabled ? startRemoteAccess() : stopRemoteAccess()
    }

    func remoteConfigurationDidChange() {
        persist()
        guard remoteEnabled else { return }
        remoteConfigurationRestart?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.remoteEnabled else { return }
            self.restartRemoteAccess()
        }
        remoteConfigurationRestart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func regenerateRemoteToken() {
        remoteToken = makeRemoteToken()
        persist()
        if remoteEnabled { restartRemoteAccess() }
    }

    func restartRemoteAccess() {
        remoteConfigurationRestart?.cancel()
        remoteConfigurationRestart = nil
        stopRemoteAccess()
        if remoteEnabled { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.startRemoteAccess() } }
    }

    func startRemoteAccess() {
        guard remoteEnabled, remoteProc == nil else { return }
        guard let node = findNodeExecutable() else {
            appendLog("⚠️ 手机远程控制无法启动：未找到 Node.js")
            return
        }
        guard listeningPid(port: remotePort) == nil else {
            appendLog("⚠️ 手机远程端口 \(remotePort) 已被占用")
            return
        }
        guard let script = Bundle.main.url(forResource: "remote-bridge", withExtension: "js") else {
            appendLog("⚠️ 手机远程控制组件缺失")
            return
        }
        do {
            try FileManager.default.createDirectory(at: remoteDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            appendLog("⚠️ 无法创建手机远程控制目录：\(error.localizedDescription)")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = [script.path]
        var environment = enrichedEnvironment()
        environment["DSH_REMOTE_PORT"] = "\(remotePort)"
        environment["DSH_TARGET_HOST"] = "127.0.0.1"
        environment["DSH_TARGET_PORT"] = "\(port)"
        environment["DSH_REMOTE_TOKEN"] = remoteToken
        environment["DSH_REMOTE_DIR"] = remoteDirectory.path
        p.environment = environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self, weak p] _ in
            DispatchQueue.main.async {
                guard let self, let p, self.remoteProc === p else { return }
                self.remoteProc = nil
                self.remoteRunning = false
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendLog(output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        do {
            try p.run()
            remoteProc = p
            remoteRunning = true
            updateRemoteStatus()
            appendLog("📱 手机远程控制已开启 → http://\(remoteAddress):\(remotePort)")
        } catch {
            appendLog("⚠️ 手机远程控制启动失败：\(error.localizedDescription)")
        }
    }

    func stopRemoteAccess() {
        remoteProc?.terminate()
        remoteProc = nil
        remoteRunning = false
        try? FileManager.default.removeItem(at: remoteDirectory.appendingPathComponent("command.json"))
    }

    private func consumeRemoteCommand() {
        guard remoteEnabled else { return }
        let file = remoteDirectory.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = object["action"] as? String else { return }
        try? FileManager.default.removeItem(at: file)
        appendLog("📱 收到手机指令：\(action)")
        switch action {
        case "start": if state.canTryStart { start() }
        case "restart":
            if ownsProcess {
                restart()
            } else if case .externalRunning = state {
                remoteRestartAfterExternalStop = true
                killExternal()
            }
        case "stop":
            if ownsProcess { stop() }
            else if case .externalRunning = state { killExternal() }
        default: break
        }
    }

    private func updateRemoteStatus() {
        guard remoteEnabled else { return }
        let snapshot: [String: Any]
        switch state {
        case .stopped: snapshot = ["state": "stopped", "label": "已停止", "detail": "可以从手机启动", "controllable": false]
        case .starting: snapshot = ["state": "starting", "label": "启动中…", "detail": "正在等待 Harness 就绪", "controllable": false]
        case .running(let pid): snapshot = ["state": "running", "label": "运行中", "detail": "PID \(pid)", "controllable": true]
        case .externalRunning(let pid): snapshot = ["state": "externalRunning", "label": "外部实例运行中", "detail": "PID \(pid)", "controllable": true]
        case .stopping: snapshot = ["state": "stopping", "label": "停止中…", "detail": "", "controllable": false]
        case .failed(let message): snapshot = ["state": "failed", "label": "运行异常", "detail": message, "controllable": false]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
        try? FileManager.default.createDirectory(at: remoteDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: remoteDirectory.appendingPathComponent("status.json"), options: .atomic)
    }

    // MARK: 日志

    func appendLog(_ s: String) {
        logLines.append(s)
        if logLines.count > 4000 { logLines.removeFirst(logLines.count - 4000) }
        logs = logLines.joined(separator: "\n")
    }

    func clearLogs() {
        logLines.removeAll()
        logs = ""
    }

    // MARK: 安装官方 DSH 运行时

    /// 用户主动点击后，通过 npm 安装官方 @deepseek-ai/dsh 到稳定的用户目录。
    /// 使用 Process 参数数组而不是 shell 字符串，避免命令注入和 PATH 差异。
    func installOfficialRuntime() {
        guard !isInstallingRuntime else { return }
        guard let npm = findNpmExecutable() else {
            state = .failed("未找到 npm，请先安装 Node.js 22.19+ 或 24+")
            appendLog("✗ 未找到 npm；请先从 https://nodejs.org/ 安装 Node.js")
            return
        }

        let prefix = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/app", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        } catch {
            state = .failed("无法创建 DSH 安装目录: \(error.localizedDescription)")
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: npm)
        p.arguments = [
            "install",
            "--prefix", prefix.path,
            "@deepseek-ai/dsh@latest",
            "--no-fund",
            "--no-audit",
        ]
        p.currentDirectoryURL = prefix
        p.environment = enrichedEnvironment()

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.finishRuntimeInstall(exitCode: process.terminationStatus, prefix: prefix)
            }
        }

        let fh = pipe.fileHandleForReading
        fh.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self?.appendLog(text) }
        }

        do {
            try p.run()
            installProc = p
            isInstallingRuntime = true
            state = .stopped
            appendLog("⬇️ 正在安装官方 @deepseek-ai/dsh → \(prefix.path)")
        } catch {
            state = .failed("启动 npm 失败: \(error.localizedDescription)")
            appendLog("✗ 启动 npm 失败: \(error.localizedDescription)")
        }
    }

    private func finishRuntimeInstall(exitCode: Int32, prefix: URL) {
        installProc = nil
        isInstallingRuntime = false
        let installed = prefix.appendingPathComponent("node_modules/.bin/dsh").path
        guard exitCode == 0, FileManager.default.isExecutableFile(atPath: installed) else {
            state = .failed("DSH 安装失败（npm 退出码 \(exitCode)），请在设置中查看日志")
            appendLog("✗ 官方 DSH 运行时安装失败（npm 退出码 \(exitCode)）")
            return
        }

        dshPath = installed
        persist()
        state = .stopped
        appendLog("✅ 官方 DSH 运行时安装完成")
        start()
    }

    // MARK: 自动启动 / 外部实例检测

    /// 打开应用时调用：检测外部实例，或按设置自动启动服务
    /// 关键修复：接管外部实例前先做真实 HTTP 健康检查——只接管「活着的」dsh；
    /// 端口被「假活」的残留进程占用时，默认自动清理后重新启动（可在设置中关闭）。
    func startIfNeeded() {
        guard let pid = listeningPid(port: port) else {
            guard autoStart else { return }
            guard case .stopped = state else { return }
            start()
            return
        }
        guard commandOf(pid: pid).contains("dsh") else {
            appendLog("⚠️ 端口 \(port) 被其他进程 (pid \(pid)) 占用，无法启动")
            return
        }
        // 端口上是 dsh 进程：后台做 HTTP 健康检查，再决定 接管 / 清理 / 启动
        let hostHere = host
        let portHere = port
        appendLog("🔍 端口 \(portHere) 上有 dsh 进程 (pid \(pid))，正在做健康检查…")
        DispatchQueue.global().async { [weak self] in
            let healthy = isHttpAlive(hostHere, portHere)
            DispatchQueue.main.async {
                self?.finishStartIfNeeded(healthy: healthy, port: portHere)
            }
        }
    }

    /// startIfNeeded 的健康检查结果处理（主线程）
    private func finishStartIfNeeded(healthy: Bool, port: Int) {
        // 健康检查期间端口状态可能已变化，重新确认
        guard let nowPid = listeningPid(port: port) else {
            start()
            return
        }
        if healthy {
            state = .externalRunning(nowPid)
            appendLog("ℹ️ 检测到已在运行的健康 dsh 实例 (pid \(nowPid))，直接使用")
        } else {
            appendLog("⚠️ 端口 \(port) 被无响应的 dsh 进程 (pid \(nowPid)) 占用")
            if cleanupStaleOnStart {
                if forceFreePort(pid: nowPid, port: port, label: "清理残留 dsh 进程") {
                    appendLog("🔄 残留进程已清理，继续启动…")
                    start()
                } else {
                    state = .failed("端口 \(port) 上的残留 dsh 进程无法清理")
                }
            } else {
                state = .failed("端口 \(port) 被无响应的 dsh 进程 (pid \(nowPid)) 占用；可在设置中开启「自动清理」")
            }
        }
    }

    func refreshExternal() {
        guard proc == nil else { return }
        let pid = listeningPid(port: port)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.handleExternalPoll(pid: pid)
        }
    }

    /// 端口轮询：发现/未发现 dsh 进程时的处理（主线程）
    private func handleExternalPoll(pid: Int32?) {
        let portHere = port
        let hostHere = host
        guard let pid = pid else {
            warnedBusy = false
            if remoteRestartAfterExternalStop {
                remoteRestartAfterExternalStop = false
                state = .stopped
                appendLog("📱 外部实例已停止，按手机指令重新启动")
                start()
                return
            }
            if case .externalRunning = state {
                state = .stopped
                appendLog("外部实例已退出")
            }
            return
        }
        let cmd = commandOf(pid: pid)
        guard cmd.contains("dsh") else {
            if !warnedBusy && state.canTryStart {
                warnedBusy = true
                appendLog("⚠️ 端口 \(portHere) 被其他进程 (pid \(pid)) 占用，无法启动")
            }
            return
        }
        // 12 秒内已对同一实例做过健康检查 → 跳过，避免频繁发起请求
        if case .externalRunning(let cur) = state, cur == pid,
           let last = lastHealthCheck, Date().timeIntervalSince(last) < 12 {
            return
        }
        lastHealthCheck = Date()
        // 真实 HTTP 健康检查放后台线程，结果回到主线程处理
        DispatchQueue.global().async { [weak self] in
            let healthy = isHttpAlive(hostHere, portHere)
            DispatchQueue.main.async {
                self?.applyExternalHealth(pid: pid, healthy: healthy, port: portHere)
            }
        }
    }

    /// 根据健康检查结果决定 接管 / 自动清理 / 报错（主线程）
    private func applyExternalHealth(pid: Int32, healthy: Bool, port: Int) {
        if healthy {
            healthFailStreak = 0
            if case .externalRunning(let cur) = state, cur == pid { return }
            state = .externalRunning(pid)
            appendLog("ℹ️ 检测到已在运行的健康 dsh 实例 (pid \(pid))，直接使用")
        } else {
            healthFailStreak += 1
            // 连续两次无响应才判定为残留，避免瞬时抖动误杀
            if healthFailStreak >= 2 {
                healthFailStreak = 0
                appendLog("⚠️ 端口 \(port) 上的 dsh 进程 (pid \(pid)) 无响应")
                if cleanupStaleOnStart {
                    state = .stopped
                    killProcess(pid: pid, label: "自动清理无响应的残留 dsh 进程")
                } else if case .externalRunning = state {
                    state = .failed("端口 \(port) 被无响应的 dsh 进程 (pid \(pid)) 占用")
                }
            }
        }
    }

    // MARK: 启动

    func start() {
        persist()
        guard !dshPath.isEmpty else {
            state = .failed("未找到 dsh 命令，请在设置中手动指定路径")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: dshPath) else {
            state = .failed("dsh 路径无效: \(dshPath)")
            return
        }
        guard case .stopped = state else { return }

        if let busy = listeningPid(port: port) {
            let isDsh = commandOf(pid: busy).contains("dsh")
            if isDsh && isHttpAlive(host, port) {
                // 端口上已有健康的 dsh 实例，直接接管而不是重复启动
                state = .externalRunning(busy)
                appendLog("ℹ️ 端口 \(port) 上已有健康的 dsh 实例 (pid \(busy))，直接使用")
                return
            }
            if isDsh && cleanupStaleOnStart {
                appendLog("⚠️ 端口 \(port) 被无响应的 dsh 进程 (pid \(busy)) 占用，自动清理后重新启动")
                if forceFreePort(pid: busy, port: port, label: "清理残留 dsh 进程") {
                    // 端口已释放，继续往下启动
                } else {
                    state = .failed("端口 \(port) 上的残留 dsh 进程无法清理")
                    return
                }
            } else {
                appendLog("⚠️ 端口 \(port) 已被进程 \(busy) 占用，无法启动")
                refreshExternal()
                return
            }
        }

        let p = Process()
        // 优先用显式 node 解释器直接运行 dsh 的 bin.js：
        // GUI 应用从 Finder/LaunchServices 启动时 PATH 往往不含任何 node，
        // 依赖 shebang `#!/usr/bin/env node` 会直接失败。
        // 显式 node + 脚本路径的方式对环境 PATH 零依赖，最稳。
        let script = resolvedScriptPath(dshPath)
        if let node = findNodeExecutable(), script.hasSuffix(".js") {
            p.executableURL = URL(fileURLWithPath: node)
            p.arguments = [script, "web", "--host", host, "--port", "\(port)", "--no-open"]
        } else {
            p.executableURL = URL(fileURLWithPath: dshPath)
            p.arguments = ["web", "--host", host, "--port", "\(port)", "--no-open"]
        }
        p.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
        // 双保险：同时补充 PATH，覆盖直接执行分支及 dsh 内部再拉起子进程的场景
        p.environment = enrichedEnvironment()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleExit() }
        }

        do {
            try p.run()
        } catch {
            state = .failed("启动失败: \(error.localizedDescription)")
            appendLog("✗ 启动失败: \(error.localizedDescription)")
            return
        }

        proc = p
        state = .starting
        appendLog("▶ 启动 dsh web → \(url.absoluteString)  (pid \(p.processIdentifier))")

        let fh = pipe.fileHandleForReading
        fh.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let s = String(data: data, encoding: .utf8) else { return }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async { self?.appendLog(trimmed) }
        }

        waitForReady()
    }

    private func waitForReady() {
        readyTimer?.invalidate()
        var tries = 0
        let hostHere = host
        let portHere = port
        readyTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            // HTTP 健康检查放后台线程，避免阻塞主线程
            DispatchQueue.global().async {
                let healthy = isHttpAlive(hostHere, portHere)
                DispatchQueue.main.async {
                    // self 已在外部闭包解包为强引用，直接使用（不再重复 guard）
                    guard self.proc != nil, self.state == .starting else { t.invalidate(); return }
                    if healthy {
                        t.invalidate()
                        self.readyTimer = nil
                        if let pid = self.proc?.processIdentifier {
                            self.state = .running(pid)
                            self.appendLog("✅ dsh web 就绪 → \(self.url.absoluteString)")
                        }
                    } else {
                        tries += 1
                        if tries > 120 { // 60 秒仍未就绪：明确报错，而不是永远停在「启动中」
                            t.invalidate()
                            self.readyTimer = nil
                            self.state = .failed("启动超时：端口 \(portHere) 60 秒内无 HTTP 响应")
                            self.appendLog("✗ 启动超时：\(self.url.absoluteString) 60 秒内无 HTTP 响应")
                        }
                    }
                }
            }
        }
    }

    private func isPortOpen(_ host: String, _ port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let name = host.isEmpty ? "127.0.0.1" : host
        guard getaddrinfo(name, "\(port)", &hints, &res) == 0, let r = res else { return false }
        defer { freeaddrinfo(r) }
        var ptr: UnsafeMutablePointer<addrinfo>? = r
        while let cur = ptr {
            let fd = socket(cur.pointee.ai_family, cur.pointee.ai_socktype, cur.pointee.ai_protocol)
            if fd >= 0 {
                var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                if connect(fd, cur.pointee.ai_addr, cur.pointee.ai_addrlen) == 0 {
                    close(fd)
                    return true
                }
                close(fd)
            }
            ptr = cur.pointee.ai_next
        }
        return false
    }

    // MARK: 停止 / 重启

    func stop() {
        guard let p = proc else { return }
        state = .stopping
        appendLog("⏹ 正在停止 (pid \(p.processIdentifier)) …")
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
                DispatchQueue.main.async {
                    self?.appendLog("进程未响应，已强制结束 (pid \(pid))")
                }
            }
        }
    }

    func restart() {
        guard proc != nil else {
            start()
            return
        }
        pendingRestart = true
        stop()
    }

    func killExternal() {
        guard case .externalRunning(let pid) = state else { return }
        state = .stopped
        killProcess(pid: pid, label: "停止外部 dsh 实例")
    }

    /// 终止进程：先 SIGTERM，4 秒后仍存活则 SIGKILL；结束后刷新端口状态
    func killProcess(pid: Int32, label: String) {
        appendLog("⏹ \(label) (pid \(pid)) …")
        if kill(pid, SIGTERM) != 0 {
            appendLog("无法向 pid \(pid) 发送信号: \(String(cString: strerror(errno)))")
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            DispatchQueue.main.async { self?.refreshExternal() }
        }
    }

    /// 同步清理占用端口的进程并等待端口释放（启动/接管前调用）；返回端口是否已空闲。
    /// 只用于「残留的无响应 dsh 进程」，阻塞主线程数秒换取确定性。
    @discardableResult
    func forceFreePort(pid: Int32, port: Int, label: String) -> Bool {
        appendLog("⏹ \(label) (pid \(pid)) …")
        if kill(pid, SIGTERM) != 0 {
            appendLog("无法向 pid \(pid) 发送信号: \(String(cString: strerror(errno)))")
            return false
        }
        for _ in 0..<6 { // 最多等 3 秒优雅退出
            usleep(500_000)
            if listeningPid(port: port) == nil { return true }
        }
        if kill(pid, SIGKILL) == 0 {
            appendLog("进程未在 3 秒内退出，已强制结束 (pid \(pid))")
        }
        for _ in 0..<4 { // 再等最多 2 秒
            usleep(500_000)
            if listeningPid(port: port) == nil { return true }
        }
        appendLog("⚠️ 端口 \(port) 仍被占用，清理未完全生效")
        return false
    }

    private func handleExit() {
        proc = nil
        readyTimer?.invalidate()
        readyTimer = nil
        appendLog("⏹ dsh web 已退出")
        if pendingRestart {
            pendingRestart = false
            state = .stopped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.start()
            }
        } else {
            state = .stopped
            refreshExternal()
        }
    }

    /// 退出应用时清理子进程（受「退出时停止服务」开关控制）
    func terminateChild() {
        installProc?.terminate()
        stopRemoteAccess()
        guard stopOnQuit else { return }
        if let p = proc {
            p.terminate()
        }
    }

    // MARK: 开机自启

    func toggleLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            appendLog("⚠️ 设置开机自启失败: \(error.localizedDescription)（请把应用放入 /Applications 后重试）")
        }
    }
}

// MARK: - 应用委托（退出时清理）

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Manager.shared.terminateChild()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - 内嵌 DSH 界面

struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        context.coordinator.lastURL = url
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        nsView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastURL: URL?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
                // 新窗口链接交给系统浏览器
                NSWorkspace.shared.open(u)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject private var mgr = Manager.shared
    @State private var showSettings = false
    @State private var confirmKillExternal = false
    @State private var showRemoteAccess = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ZStack {
                if mgr.state.webReady {
                    WebView(url: mgr.url)
                } else {
                    placeholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 920, minHeight: 620)
        .onAppear { mgr.startIfNeeded() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showRemoteAccess) {
            RemoteAccessView()
        }
        .alert("停止外部实例", isPresented: $confirmKillExternal) {
            Button("停止", role: .destructive) { mgr.killExternal() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向外部 dsh 进程发送终止信号。该进程不是由本应用启动的，确定要停止它吗？")
        }
    }

    // MARK: 工具栏

    private var toolbar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText).font(.system(.body, weight: .medium))
            Text(mgr.url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { mgr.start() }) {
                Label("启动", systemImage: "play.fill")
            }
            .disabled(!mgr.canStart)

            Button(action: { mgr.stop() }) {
                Label("停止", systemImage: "stop.fill")
            }
            .disabled(!mgr.ownsProcess)

            Button(action: { mgr.restart() }) {
                Label("重启", systemImage: "arrow.clockwise")
            }
            .disabled(!mgr.ownsProcess)

            Button(action: { NSWorkspace.shared.open(mgr.url) }) {
                Label("系统浏览器", systemImage: "safari")
            }
            .disabled(!mgr.state.portActive)

            if case .externalRunning(let pid) = mgr.state {
                Button(action: { confirmKillExternal = true }) {
                    Label("接管并停止", systemImage: "xmark.circle")
                }
                .help("停止由其他方式启动的 dsh (pid \(pid))")
            }

            Divider().frame(height: 18)

            Button(action: { showRemoteAccess = true }) {
                Label("手机", systemImage: "iphone.gen3")
            }

            Button(action: { showSettings = true }) {
                Label("设置", systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusText: String {
        if mgr.isInstallingRuntime { return "正在安装 DSH…" }
        switch mgr.state {
        case .stopped: return "已停止"
        case .starting: return "启动中…"
        case .running(let pid): return "运行中 (pid \(pid))"
        case .externalRunning(let pid): return "运行中 · 外部实例 (pid \(pid))"
        case .stopping: return "停止中…"
        case .failed(let msg): return "异常：\(msg)"
        }
    }

    private var statusColor: Color {
        if mgr.isInstallingRuntime { return .orange }
        switch mgr.state {
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .running, .externalRunning: return .green
        case .failed: return .red
        }
    }

    // MARK: 未运行时的占位页

    private var placeholderView: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("DSH 服务未运行").font(.title3).bold()
            Text(mgr.url.absoluteString)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
            if mgr.isInstallingRuntime {
                ProgressView().controlSize(.small)
                Text("正在通过 npm 安装官方 @deepseek-ai/dsh…")
                    .foregroundColor(.secondary)
                Text("安装完成后将自动启动服务")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if mgr.dshPath.isEmpty {
                if case .failed(let msg) = mgr.state {
                    Text(msg).foregroundColor(.red).font(.callout)
                } else {
                    Text("未找到 DeepSeek Harness 运行时")
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Button(action: { mgr.installOfficialRuntime() }) {
                    Label("一键安装官方 DSH 运行时", systemImage: "arrow.down.circle.fill")
                }
                .controlSize(.large)
                Text("需要 Node.js 22.19+ 或 24+；运行时将安装到 ~/.dsh/app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if mgr.state == .stopped {
                Button(action: { mgr.start() }) {
                    Label("启动服务", systemImage: "play.fill")
                }
                .controlSize(.large)
                .disabled(!mgr.canStart)
            } else if case .failed(let msg) = mgr.state {
                Text(msg).foregroundColor(.red).font(.callout)
            } else {
                ProgressView().controlSize(.small)
                Text("正在启动…").foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - 手机远程控制

struct QRCodeView: View {
    let value: String

    var body: some View {
        if let image = makeImage() {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 196, height: 196)
                .padding(10)
                .background(Color.white)
                .cornerRadius(16)
        }
    }

    private func makeImage() -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

struct RemoteAccessView: View {
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("手机远程控制").font(.title2).bold()
                    Text("像 Codex Mobile 一样，在手机浏览器控制这台电脑上的 DSH")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { mgr.remoteEnabled }, set: { mgr.setRemoteEnabled($0) }))
                    .toggleStyle(.switch)
            }

            if mgr.remoteEnabled {
                if mgr.remoteRunning, let pairing = mgr.remotePairingURL {
                    QRCodeView(value: pairing.absoluteString)
                    VStack(spacing: 7) {
                        Label("桥接服务已运行", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("手机与电脑连接同一 Wi-Fi 后扫码")
                            .font(.headline)
                        Text("也可以在手机打开：\(mgr.remoteDashboardURL?.absoluteString ?? "")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("在本机预览") {
                            if let url = mgr.remotePairingURL { NSWorkspace.shared.open(url) }
                        }
                        Button("复制配对链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pairing.absoluteString, forType: .string)
                        }
                        Button("重置配对", role: .destructive) { mgr.regenerateRemoteToken() }
                    }
                    Text("完整 DSH 仍只监听本机；手机流量经过带配对会话的代理。若要在外网使用，请让电脑和手机加入同一个 Tailscale 网络。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                } else {
                    ProgressView("正在启动手机桥接服务…")
                    Button("重试") { mgr.startRemoteAccess() }
                }
            } else {
                Image(systemName: "iphone.slash")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary)
                Text("开启后会在局域网端口 \(mgr.remotePort) 提供带配对保护的手机入口。")
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
        .frame(minHeight: 510)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject private var mgr = Manager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmKillExternal = false

    private let portFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 65535
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置").font(.title2).bold()

            GroupBox(label: Label("服务", systemImage: "server.rack")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text("端口:")
                        TextField("3080", value: $mgr.port, formatter: portFormatter)
                            .frame(width: 90)
                        Text("主机:")
                        TextField("127.0.0.1", text: $mgr.host)
                            .frame(width: 130)
                        Spacer()
                    }
                    HStack(spacing: 20) {
                        Toggle("打开应用时自动启动服务", isOn: $mgr.autoStart)
                        Toggle("退出应用时停止服务", isOn: $mgr.stopOnQuit)
                        Toggle("开机自启", isOn: $mgr.launchAtLogin)
                            .onChange(of: mgr.launchAtLogin) { newValue in
                                mgr.toggleLaunchAtLogin(newValue)
                            }
                    }
                    HStack(spacing: 20) {
                        Toggle("启动时自动清理无响应的残留 dsh 进程", isOn: $mgr.cleanupStaleOnStart)
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        Text("dsh 路径:")
                        TextField("", text: $mgr.dshPath)
                            .font(.system(.body, design: .monospaced))
                        Button("浏览…") { pickPath() }
                        if !FileManager.default.isExecutableFile(atPath: mgr.dshPath) {
                            Button("安装官方版本") { mgr.installOfficialRuntime() }
                                .disabled(mgr.isInstallingRuntime)
                        }
                        if FileManager.default.isExecutableFile(atPath: mgr.dshPath) {
                            Text("✓ 有效").foregroundColor(.green)
                        } else {
                            Text("✗ 无效").foregroundColor(.red)
                        }
                    }
                    HStack {
                        Text("修改端口/主机后，请点击「重启」让服务生效。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if case .externalRunning(let pid) = mgr.state {
                            Button(role: .destructive) { confirmKillExternal = true } label: {
                                Label("停止外部实例 (pid \(pid))", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(4)
            }

            GroupBox(label: Label("手机远程控制", systemImage: "iphone.gen3")) {
                HStack(spacing: 12) {
                    Toggle("启用手机桥接", isOn: Binding(get: { mgr.remoteEnabled }, set: { mgr.setRemoteEnabled($0) }))
                    Text("端口:")
                    TextField("3081", value: $mgr.remotePort, formatter: portFormatter)
                        .frame(width: 80)
                    Text(mgr.remoteRunning ? "● 已运行" : "○ 未运行")
                        .foregroundColor(mgr.remoteRunning ? .green : .secondary)
                    Spacer()
                    Button("重启桥接") { mgr.restartRemoteAccess() }
                        .disabled(!mgr.remoteEnabled)
                }
                .padding(4)
            }

            GroupBox(label: Label("日志", systemImage: "text.alignleft")) {
                VStack(alignment: .leading, spacing: 6) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(mgr.logs.isEmpty ? "（暂无日志）" : mgr.logs)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("logtail")
                                .padding(8)
                        }
                        .frame(height: 180)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(6)
                        .onChange(of: mgr.logs) { _ in
                            withAnimation(.none) { proxy.scrollTo("logtail", anchor: .bottom) }
                        }
                    }
                    Button("清空日志") { mgr.clearLogs() }
                        .controlSize(.small)
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 640)
        .onChange(of: mgr.port) { _ in mgr.remoteConfigurationDidChange(); mgr.refreshExternal() }
        .onChange(of: mgr.host) { _ in mgr.persist() }
        .onChange(of: mgr.dshPath) { _ in mgr.persist() }
        .onChange(of: mgr.autoStart) { _ in mgr.persist() }
        .onChange(of: mgr.stopOnQuit) { _ in mgr.persist() }
        .onChange(of: mgr.cleanupStaleOnStart) { _ in mgr.persist() }
        .onChange(of: mgr.remotePort) { _ in mgr.remoteConfigurationDidChange() }
        .alert("停止外部实例", isPresented: $confirmKillExternal) {
            Button("停止", role: .destructive) { mgr.killExternal() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将向外部 dsh 进程发送终止信号。该进程不是由本应用启动的，确定要停止它吗？")
        }
    }

    private func pickPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择 dsh 可执行文件"
        panel.message = "请选择 dsh 命令（例如 ~/.npm/_npx/*/node_modules/.bin/dsh）"
        if panel.runModal() == .OK, let u = panel.url {
            mgr.dshPath = u.path
            mgr.persist()
        }
    }
}

// MARK: - 应用入口

@main
struct DSHLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("DSH Desktop") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
