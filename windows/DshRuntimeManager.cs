using System.Diagnostics;
using System.Net;

namespace DSHDesktop.Windows;

internal sealed class DshRuntimeManager : IDisposable
{
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(2) };
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly System.Threading.Timer _watchTimer;
    private Process? _serviceProcess;
    private Process? _installProcess;
    private bool _disposed;

    public DshRuntimeManager(string host = "127.0.0.1", int port = 3080)
    {
        Host = host;
        Port = port;
        State = new RuntimeState(RuntimeStatus.Stopped, "Stopped");
        _watchTimer = new System.Threading.Timer(
            async _ => await PollHealthAsync().ConfigureAwait(false),
            null,
            Timeout.Infinite,
            Timeout.Infinite);
    }

    public string Host { get; }
    public int Port { get; }
    public Uri ServiceUri => new($"http://{Host}:{Port}");
    public string? DshScriptPath => FindDshScript();
    public bool NodeAvailable => FindNodeExecutable() is not null;
    public RuntimeState State { get; private set; }

    public event Action<RuntimeState>? StateChanged;
    public event Action<string>? LogReceived;

    public async Task InitializeAsync()
    {
        _watchTimer.Change(TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(5));
        if (await IsHealthyAsync().ConfigureAwait(false))
        {
            SetState(RuntimeStatus.ExternalRunning, "Running · external instance");
            return;
        }

        if (DshScriptPath is not null)
        {
            await StartAsync().ConfigureAwait(false);
        }
        else
        {
            SetState(RuntimeStatus.Stopped, "Official DSH runtime not found");
        }
    }

    public async Task InstallOfficialRuntimeAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (State.Status == RuntimeStatus.Installing)
            {
                return;
            }

            var node = FindNodeExecutable();
            var npmCli = node is null ? null : FindNpmCli(node);
            if (node is null || npmCli is null)
            {
                SetState(RuntimeStatus.Failed, "Node.js 22.19+ or 24+ is required");
                WriteLog("Node.js/npm was not found. Install Node.js from https://nodejs.org/ and retry.");
                return;
            }

            var prefix = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".dsh",
                "app");
            Directory.CreateDirectory(prefix);

            var startInfo = CreateNodeStartInfo(node);
            startInfo.ArgumentList.Add(npmCli);
            startInfo.ArgumentList.Add("install");
            startInfo.ArgumentList.Add("--prefix");
            startInfo.ArgumentList.Add(prefix);
            startInfo.ArgumentList.Add("@deepseek-ai/dsh@latest");
            startInfo.ArgumentList.Add("--no-fund");
            startInfo.ArgumentList.Add("--no-audit");
            startInfo.WorkingDirectory = prefix;

            SetState(RuntimeStatus.Installing, "Installing official DSH runtime…");
            WriteLog($"Installing official @deepseek-ai/dsh into {prefix}");
            _installProcess = StartCapturedProcess(startInfo, "npm");
        }
        finally
        {
            _gate.Release();
        }

        if (_installProcess is null)
        {
            return;
        }

        await _installProcess.WaitForExitAsync().ConfigureAwait(false);
        var exitCode = _installProcess.ExitCode;
        _installProcess.Dispose();
        _installProcess = null;

        if (exitCode != 0 || DshScriptPath is null)
        {
            SetState(RuntimeStatus.Failed, $"DSH installation failed (npm exit code {exitCode})");
            return;
        }

        WriteLog("Official DSH runtime installed successfully.");
        SetState(RuntimeStatus.Stopped, "DSH installed");
        await StartAsync().ConfigureAwait(false);
    }

    public async Task StartAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (State.Status is RuntimeStatus.Starting or RuntimeStatus.Running or RuntimeStatus.Installing)
            {
                return;
            }
            if (await IsHealthyAsync().ConfigureAwait(false))
            {
                SetState(RuntimeStatus.ExternalRunning, "Running · external instance");
                return;
            }

            var node = FindNodeExecutable();
            var script = DshScriptPath;
            if (node is null)
            {
                SetState(RuntimeStatus.Failed, "Node.js 22.19+ or 24+ is required");
                return;
            }
            if (script is null)
            {
                SetState(RuntimeStatus.Stopped, "Official DSH runtime not found");
                return;
            }

            var startInfo = CreateNodeStartInfo(node);
            startInfo.ArgumentList.Add(script);
            startInfo.ArgumentList.Add("web");
            startInfo.ArgumentList.Add("--host");
            startInfo.ArgumentList.Add(Host);
            startInfo.ArgumentList.Add("--port");
            startInfo.ArgumentList.Add(Port.ToString());
            startInfo.ArgumentList.Add("--no-open");
            startInfo.WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

            SetState(RuntimeStatus.Starting, "Starting DSH…");
            _serviceProcess = StartCapturedProcess(startInfo, "dsh");
            _serviceProcess.EnableRaisingEvents = true;
            _serviceProcess.Exited += (_, _) => HandleServiceExit();
            WriteLog($"Starting dsh web at {ServiceUri}");
        }
        catch (Exception ex)
        {
            SetState(RuntimeStatus.Failed, $"Failed to start DSH: {ex.Message}");
            return;
        }
        finally
        {
            _gate.Release();
        }

        for (var attempt = 0; attempt < 120; attempt++)
        {
            if (_serviceProcess is null || _serviceProcess.HasExited)
            {
                return;
            }
            if (await IsHealthyAsync().ConfigureAwait(false))
            {
                SetState(RuntimeStatus.Running, $"Running · pid {_serviceProcess.Id}");
                WriteLog($"DSH Web UI is ready at {ServiceUri}");
                return;
            }
            await Task.Delay(500).ConfigureAwait(false);
        }

        SetState(RuntimeStatus.Failed, "DSH startup timed out after 60 seconds");
    }

    public async Task StopAsync()
    {
        Process? process;
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            process = _serviceProcess;
            if (process is null || process.HasExited)
            {
                SetState(RuntimeStatus.Stopped, "Stopped");
                return;
            }
            SetState(RuntimeStatus.Stopping, "Stopping DSH…");
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // The process exited between the state check and Kill.
            }
        }
        finally
        {
            _gate.Release();
        }

        if (process is not null)
        {
            await process.WaitForExitAsync().ConfigureAwait(false);
        }
        SetState(RuntimeStatus.Stopped, "Stopped");
    }

    public async Task RestartAsync()
    {
        await StopAsync().ConfigureAwait(false);
        await StartAsync().ConfigureAwait(false);
    }

    private Process StartCapturedProcess(ProcessStartInfo startInfo, string label)
    {
        var process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) WriteLog(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (!string.IsNullOrWhiteSpace(e.Data)) WriteLog(e.Data); };
        if (!process.Start())
        {
            throw new InvalidOperationException($"Could not start {label}.");
        }
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return process;
    }

    private static ProcessStartInfo CreateNodeStartInfo(string node) => new()
    {
        FileName = node,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true,
    };

    private async Task<bool> IsHealthyAsync()
    {
        try
        {
            using var response = await _http.GetAsync(ServiceUri).ConfigureAwait(false);
            return (int)response.StatusCode is >= 100 and <= 599;
        }
        catch
        {
            return false;
        }
    }

    private async Task PollHealthAsync()
    {
        if (_disposed || State.Status is RuntimeStatus.Installing or RuntimeStatus.Starting or RuntimeStatus.Stopping)
        {
            return;
        }

        var healthy = await IsHealthyAsync().ConfigureAwait(false);
        if (healthy && State.Status == RuntimeStatus.Stopped)
        {
            SetState(RuntimeStatus.ExternalRunning, "Running · external instance");
        }
        else if (!healthy && State.Status == RuntimeStatus.ExternalRunning)
        {
            SetState(RuntimeStatus.Stopped, "External DSH instance stopped");
        }
    }

    private void HandleServiceExit()
    {
        if (_disposed)
        {
            return;
        }
        _serviceProcess?.Dispose();
        _serviceProcess = null;
        if (State.Status != RuntimeStatus.Stopping)
        {
            SetState(RuntimeStatus.Stopped, "DSH process exited");
        }
    }

    private static string? FindDshScript()
    {
        var user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var candidates = new[]
        {
            Path.Combine(user, ".dsh", "app", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js"),
            Path.Combine(appData, "npm", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? FindNodeExecutable()
    {
        var candidates = new List<string>
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "nodejs", "node.exe"),
        };
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        candidates.AddRange(path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Select(directory => Path.Combine(directory.Trim('"'), "node.exe")));
        return candidates.FirstOrDefault(File.Exists);
    }

    private static string? FindNpmCli(string node)
    {
        var nodeDirectory = Path.GetDirectoryName(node) ?? string.Empty;
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var candidates = new[]
        {
            Path.Combine(nodeDirectory, "node_modules", "npm", "bin", "npm-cli.js"),
            Path.Combine(appData, "npm", "node_modules", "npm", "bin", "npm-cli.js"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private void SetState(RuntimeStatus status, string message)
    {
        State = new RuntimeState(status, message);
        StateChanged?.Invoke(State);
    }

    private void WriteLog(string message)
    {
        LogReceived?.Invoke($"[{DateTime.Now:HH:mm:ss}] {message}");
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _watchTimer.Dispose();
        try { _installProcess?.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
        try { _serviceProcess?.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
        _installProcess?.Dispose();
        _serviceProcess?.Dispose();
        _http.Dispose();
        _gate.Dispose();
    }
}
