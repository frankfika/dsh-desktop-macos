# DSH Desktop for macOS

[中文说明](#中文说明) · [Download](https://github.com/frankfika/dsh-desktop-macos/releases/latest) · [Report a bug](https://github.com/frankfika/dsh-desktop-macos/issues)

A tiny native macOS desktop shell for the official
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI. It starts and
stops the local `dsh` service, embeds the UI in a `WKWebView`, and keeps the runtime logs
and common controls in one window.

> This is an independent community project. It is not an official DeepSeek product and
> is not affiliated with or endorsed by DeepSeek. DeepSeek Harness is installed separately
> from the official `@deepseek-ai/dsh` npm package.

## Features

- Native SwiftUI + WebKit app with no third-party app dependencies
- Universal binary for Apple Silicon and Intel Macs
- Detects an existing healthy `dsh web` process or starts one automatically
- Start, stop, restart, open in browser, launch at login, and live logs
- Detects Homebrew, npm, nvm, WorkBuddy, and the recommended local installation path
- Cleans up an unresponsive `dsh` process after confirming that its local HTTP endpoint
  is unhealthy

## Requirements

- macOS 13 Ventura or newer
- Node.js 22.19+ or 24+
- The official `@deepseek-ai/dsh` package

DeepSeek Harness is currently a developer preview. It can run tools that read or modify
the workspace you select. Start with a disposable project, use limited credentials, and
review approval requests.

## Install

Install [Node.js](https://nodejs.org/) first, then use the verified community installer:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/frankfika/dsh-desktop-macos/main/install.sh)"
```

The installer downloads the latest ZIP from GitHub Releases, verifies its SHA-256
checksum, installs the app, removes quarantine only from that app bundle, installs the
official `@deepseek-ai/dsh` runtime, and launches DSH Desktop. Review
[install.sh](install.sh) before running it if you prefer.

You can also download the universal `.dmg` from
[GitHub Releases](https://github.com/frankfika/dsh-desktop-macos/releases/latest) and
install manually. The community build is ad-hoc signed because the project does not yet
have an Apple Developer ID certificate. For a manual first launch, Control-click the app
in Finder, choose **Open**, then confirm **Open**.

## Build from source

Xcode Command Line Tools are sufficient:

```bash
git clone https://github.com/frankfika/dsh-desktop-macos.git
cd dsh-desktop-macos
./build.sh
open ".build/DSH Desktop.app"
```

`build.sh` produces an ad-hoc-signed universal app by default. To build only for the
current architecture:

```bash
ARCHS="$(uname -m)" ./build.sh
```

Create local ZIP and DMG artifacts with:

```bash
./scripts/package.sh
```

Pushing a tag such as `v1.0.2` runs the GitHub Actions release workflow and attaches the
universal ZIP, DMG, and SHA-256 checksums to a GitHub Release.

## Project structure

```text
Sources/DSHLauncher.swift  Process lifecycle, SwiftUI window, and embedded Web UI
tools/IconGen.swift        Programmatic app icon generator
Info.plist                 macOS bundle metadata
build.sh                   Reproducible universal app build
install.sh                 Verified community installer
scripts/package.sh         ZIP, DMG, and checksum packaging
.github/workflows/         Continuous integration and tagged releases
```

## Security and privacy

DSH Desktop talks only to the loopback service address configured in the app. Model
credentials and session data are owned by DeepSeek Harness, not by this launcher. Do not
bind the DSH Web service to a public network interface without authentication and TLS.
See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

DSH Desktop is released under the [MIT License](LICENSE). DeepSeek Harness is a separate
project distributed under its own MIT license and third-party notices.

---

## 中文说明

DSH Desktop 是官方
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI 的轻量原生
macOS 桌面壳。它负责启动和停止本机 `dsh` 服务、把网页界面嵌入桌面窗口，并集中提供
重启、浏览器打开、开机自启和日志查看。

本项目是独立社区项目，不是 DeepSeek 官方产品，也不与 DeepSeek 存在隶属或背书关系；
DeepSeek Harness 运行时始终从官方 npm 包 `@deepseek-ai/dsh` 单独安装。

### 安装

先安装 Node.js 22.19+ 或 24+，再在终端运行社区验证安装器：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/frankfika/dsh-desktop-macos/main/install.sh)"
```

安装器会从 GitHub Release 下载最新版 ZIP、核对 SHA-256、安装应用、仅移除该 App 的
隔离标记、安装官方 `@deepseek-ai/dsh` 运行时并启动应用。运行前可先查看仓库中的
[install.sh](install.sh) 源码。

也可以从 [Releases](https://github.com/frankfika/dsh-desktop-macos/releases/latest) 下载
通用 `.dmg` 手动安装。目前发布包使用临时签名，因为项目尚无 Apple Developer ID；手动
安装后第一次打开时，请在 Finder 里按住 Control 点击应用，选择“打开”，再次确认。

DeepSeek Harness 仍处于开发者预览阶段，智能体可能读取或修改你选择的工作目录。建议先在
临时项目中使用受限凭据测试，并认真检查每一次权限确认。
