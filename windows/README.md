# DSH Desktop for Windows

Native Windows 10/11 desktop shell for the official DeepSeek Harness Web UI.

## User requirements

- Windows 10 or Windows 11, x64 or ARM64
- Node.js 22.19+ or 24+
- Microsoft Edge WebView2 Runtime (normally already present on supported Windows systems)

The release is self-contained and does not require a separate .NET installation.

If the official DSH runtime is missing, click **Install official DSH runtime**. The app
invokes npm directly and installs `@deepseek-ai/dsh@latest` into
`%USERPROFILE%\.dsh\app`, then starts the local Web UI automatically.

## Build

```powershell
dotnet restore .\windows\DSHDesktop.Windows.csproj
dotnet publish .\windows\DSHDesktop.Windows.csproj `
  --configuration Release `
  --runtime win-x64 `
  --self-contained true
```

GitHub Actions builds and smoke-tests x64, cross-builds ARM64, and attaches portable ZIP
archives to tagged releases.
