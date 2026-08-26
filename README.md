# DSH Desktop for macOS and Windows

[中文说明](#中文说明) · [Download](https://github.com/frankfika/dsh-desktop-macos/releases/latest) · [Report a bug](https://github.com/frankfika/dsh-desktop-macos/issues)

A native desktop shell for the official
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI on macOS and
Windows. It starts and stops the local `dsh` service, embeds the UI using WKWebView on
macOS or Microsoft Edge WebView2 on Windows, and keeps runtime logs and common controls
in one window.

> This is an independent community project. It is not an official DeepSeek product and
> is not affiliated with or endorsed by DeepSeek. DeepSeek Harness is installed separately
> from the official `@deepseek-ai/dsh` npm package.

## macOS Quick Install / macOS 快速安装

Install [Node.js 22.19+ or 24+](https://nodejs.org/), then run this command in Terminal：
先安装 Node.js 22.19+ 或 24+，再在终端运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/frankfika/dsh-desktop-macos/main/install.sh)"
```

The open-source installer verifies the GitHub Release SHA-256 before installing and
removes quarantine only from the verified DSH Desktop bundle. It also installs the
official `@deepseek-ai/dsh` runtime and launches the app.

开源安装器会先校验 GitHub Release 的 SHA-256，再安装应用；它只解除校验通过的 DSH
Desktop 应用隔离属性，同时安装官方 `@deepseek-ai/dsh` 运行时并启动应用。

## Windows Download / Windows 下载

Download the appropriate portable ZIP from
[the latest Release](https://github.com/frankfika/dsh-desktop-macos/releases/latest):

- `DSH-Desktop-Windows-win-x64-*.zip` for most Intel/AMD Windows computers
- `DSH-Desktop-Windows-win-arm64-*.zip` for Windows on ARM

Extract the ZIP and run **DSH Desktop.exe**. The Windows build is self-contained, so .NET
does not need to be installed. Node.js 22.19+ or 24+ is still required. If DSH is missing,
click **Install official DSH runtime** inside the app; it installs the official npm package
to `%USERPROFILE%\.dsh\app` and starts the service automatically.

从最新 Release 下载对应的 Windows 便携 ZIP，解压后运行 **DSH Desktop.exe**。大多数
电脑选择 `win-x64`，Windows ARM 设备选择 `win-arm64`。应用已包含 .NET 运行时；仍需
Node.js 22.19+ 或 24+。如果没有 DSH，在应用中点击 **Install official DSH runtime**
即可安装官方 npm 包并自动启动。

## Features

- Native SwiftUI + WebKit app with no third-party app dependencies
- Universal binary for Apple Silicon and Intel Macs
- Native Windows 10/11 app using WinForms and Microsoft Edge WebView2
- Self-contained Windows x64 and ARM64 builds with no separate .NET requirement
- Detects an existing healthy `dsh web` process or starts one automatically
- Start, stop, restart, open in browser, launch at login, and live logs
- Pair a phone by QR code, control the desktop runtime, and use the complete DSH Web UI
  through an authenticated local proxy (macOS)
- Detects Homebrew, npm, nvm, WorkBuddy, and the recommended local installation path
- Offers one-click installation of the official `@deepseek-ai/dsh` runtime when missing
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

If the app was installed manually and cannot find DSH, its first-run screen provides an
**Install official DSH runtime** button. The app invokes npm directly without a shell and
installs the official package into `~/.dsh/app`, then starts the service automatically.

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

## Control DSH from your phone (macOS)

1. Open **DSH Desktop** and click **Phone / 手机** in the toolbar.
2. Turn on mobile remote control. Keep the Mac and phone on the same Wi-Fi network.
3. Scan the QR code with the phone. The one-time link stores a protected pairing session
   in the phone browser and immediately removes the token from the address bar.
4. The mobile dashboard can start, stop, or restart the DSH process. Tap **Open complete
   DeepSeek Harness** to use the normal Harness UI from the phone. On iPhone, Safari's
   **Add to Home Screen** makes it behave like a lightweight companion app.

DSH itself continues to listen only on `127.0.0.1`. DSH Desktop runs a separate bridge on
port `3081`, checks a random per-install pairing token, and proxies both HTTP and WebSocket
traffic. You can change the bridge port or reset all paired phones from the desktop app.
For access away from home, connect the Mac and phone with an encrypted private network such
as Tailscale; do not forward port `3081` directly from a public router because the local
bridge intentionally uses HTTP and relies on the trusted LAN or encrypted overlay network.

### Native iPhone companion

The repository also includes a native SwiftUI client in `ios/`. It provides camera QR
pairing, Keychain-backed credentials, a native status/control dashboard, pull to refresh,
and an authenticated in-app Harness browser.

```bash
cd ios
./generate.sh
open DSHMobile.xcodeproj
```

Select the `DSHMobile` scheme and your iPhone, choose your Apple development team under
Signing & Capabilities, then press Run. In DSH Mobile, scan the QR code shown by the Mac
app. The deployment target is iOS 17.

### Native Android companion

The native Android client lives in `android/` and supports Android 8.0 (API 26) or newer.
It uses Google Code Scanner for permission-free QR pairing, Android Keystore AES-GCM for
the pairing credential, a native status/control dashboard, and an authenticated WebView
for the full Harness UI.

```bash
cd android
./build_and_verify.sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The verification script runs unit tests, builds the debug APK, and requires Android Lint
to pass. For normal installation, download the signed `DSH-Mobile-Android-*.apk` from the
latest GitHub Release. On a phone, open DSH Mobile and scan the same QR code shown by DSH Desktop.

`build.sh` produces an ad-hoc-signed universal app by default. To build only for the
current architecture:

```bash
ARCHS="$(uname -m)" ./build.sh
```

Create local ZIP and DMG artifacts with:

```bash
./scripts/package.sh
```

Pushing a tag such as `v1.2.0` runs the GitHub Actions release workflow and attaches the
universal macOS ZIP/DMG, Windows portable builds, signed Android APK, and SHA-256 checksums
to a GitHub Release.

## Project structure

```text
Sources/DSHLauncher.swift  Process lifecycle, SwiftUI window, and embedded Web UI
Resources/remote-bridge.js Authenticated mobile dashboard and HTTP/WebSocket proxy
ios/                       Native DSH Mobile iPhone app and generated Xcode project
android/                   Native DSH Mobile Android app, Gradle wrapper, tests, and APK build
tools/IconGen.swift        Programmatic app icon generator
Info.plist                 macOS bundle metadata
build.sh                   Reproducible universal app build
install.sh                 Verified community installer
script/build_and_run.sh    Local build, launch, and verification entrypoint
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

如果手动安装 App 且本机没有 DSH，首次启动页面会显示“一键安装官方 DSH 运行时”按钮。
应用会直接调用 npm（不经过 shell）将官方包安装到 `~/.dsh/app`，完成后自动启动服务。

也可以从 [Releases](https://github.com/frankfika/dsh-desktop-macos/releases/latest) 下载
通用 `.dmg` 手动安装。目前发布包使用临时签名，因为项目尚无 Apple Developer ID；手动
安装后第一次打开时，请在 Finder 里按住 Control 点击应用，选择“打开”，再次确认。

DeepSeek Harness 仍处于开发者预览阶段，智能体可能读取或修改你选择的工作目录。建议先在
临时项目中使用受限凭据测试，并认真检查每一次权限确认。
