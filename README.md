# DSH 桌面版 (DSH Desktop)

原生 macOS 桌面应用：**打开应用就是 DeepSeek Harness**——服务由应用自动启动，
主窗口直接内嵌 DSH 的 Web 界面，无需再开浏览器。

- 纯 SwiftUI + WKWebView 编写，无第三方依赖，二进制约 330KB
- **打开即用**：自动检测端口上的 dsh 实例（外部实例直接接管显示），否则按设置自动启动服务
- 主窗口就是 DSH 界面；工具栏一键 **启动 / 停止 / 重启 / 在系统浏览器打开**
- 自动探测 dsh 命令路径（扫描 `~/.npm/_npx/*/node_modules/.bin/dsh` 等位置）
- 设置面板：端口 / 主机 / 自动启动 / 退出时停止 / 开机自启 / dsh 路径 / 实时日志
- 退出应用时默认随服务一起停止（可在设置中关闭）

## 构建

```bash
cd ~/Desktop/DSH-Launcher
./build.sh
```

构建产物：`.build/DSH 桌面版.app`。打开方式：

```bash
open ".build/DSH 桌面版.app"
```

### 安装到应用程序目录（推荐）

```bash
cp -R ".build/DSH 桌面版.app" /Applications/
open /Applications/DSH\ 桌面版.app
```

> 注意：「开机自启」功能要求应用位于 `/Applications` 下才生效。

## 使用说明

1. 打开应用，自动进入 DSH 界面：
   - 端口上已有 dsh 在运行 → 直接嵌入显示（顶部显示「运行中 · 外部实例」）；
   - 没有运行且「自动启动」开启 → 自动启动服务，就绪后自动加载界面；
   - 服务未运行时会显示占位页，点「启动服务」即可。
2. 工具栏：状态灯 + 服务地址 + 启动/停止/重启 + 在系统浏览器打开 + 设置。
3. 「接管并停止」按钮（出现于外部实例时）用于终止不是本应用启动的 dsh 进程。
4. 设置面板可修改端口、主机、dsh 路径，并查看实时日志；修改端口/主机后点「重启」生效。

## 目录结构

```
DSH-Launcher/
├── Sources/
│   └── DSHLauncher.swift   # 主程序（进程管理 / 工具栏 / 内嵌界面 / 设置）
├── tools/
│   └── IconGen.swift       # 图标生成器（CoreGraphics 绘制）
├── Info.plist              # 应用配置
├── build.sh                # 一键构建脚本
└── .build/                 # 构建产物（由脚本生成，已隐藏）
```

## 已知问题与解决

### 编译报错：`redefinition of module 'SwiftBridging'`

新版 macOS CommandLineTools 的 `usr/include/swift/` 下同时存在
`module.modulemap` 和 `bridging.modulemap`，二者都定义了 `SwiftBridging` 模块，
导致任何 `import Foundation` 都会失败。这是 Apple 的 CLT 打包缺陷。

`build.sh` 会自动检测并应用补丁：拷贝一份 include 到 `/tmp/dsh-launcher-crt`，
删掉冲突的 `module.modulemap`，再用 `-resource-dir` 让编译器使用补丁目录——
**不需要 sudo，不修改系统文件**。

根治办法（可选，需要管理员权限）：

```bash
sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
```

### dsh 路径无效

在设置中点击「浏览…」，手动选择 dsh 可执行文件
（例如 `~/.npm/_npx/xxxxxxxx/node_modules/.bin/dsh`）。

> 推荐：把 dsh 及其依赖安装到稳定位置 `~/.dsh/app/node_modules`（应用会优先探测
> `~/.dsh/app/node_modules/.bin/dsh`），避免 npx 缓存被清理后路径失效。

### GUI 环境找不到 node（打开应用服务起不来）

从 Finder/启动台打开时，macOS 给 GUI 应用的 PATH 不含 Homebrew/nvm/workbuddy 的
node，dsh 脚本的 `#!/usr/bin/env node` shebang 会找不到解释器导致启动失败。
应用已内置修复：启动服务时自动定位 node 可执行文件（`/opt/homebrew/bin/node`、
`~/.nvm/...`、`~/.workbuddy/binaries/node/...`），用 `node bin.js web ...` 显式
运行，同时为子进程补充 PATH，双保险。

### 端口被其他进程占用

状态栏会提示占用进程的 PID。修改端口后点「重启」即可。

### 启动白屏 / 点图标没反应（残留进程占用端口）

上次强制退出、合盖睡眠或进程被杀后，可能残留一个**占着端口但无响应的 dsh 进程**
（端口连通但 HTTP 不响应）。这类"假活"进程会让应用误以为服务在运行，内嵌页面白屏。

应用现在在接管 / 启动前都会做**真实 HTTP 健康检查**（不再是仅 TCP 连通性）：

- 端口上有**健康**的 dsh 实例 → 直接接管显示；
- 端口被**无响应**的残留 dsh 进程占用 → 默认**自动清理后重新启动**
  （可在设置中关闭：`启动时自动清理无响应的残留 dsh 进程`）；
- 启动后 60 秒内服务无 HTTP 响应 → 明确报「启动超时」，不再永远停在「启动中」；
- 运行期间每 12 秒复查一次健康状态，连续两次无响应也会自动清理。

手动自救（症状：点图标没反应或白屏）：

```bash
lsof -iTCP:3090   # 看端口被谁占着
kill <PID>        # 杀掉残留进程
open "/Applications/DSH 桌面版.app"
```
