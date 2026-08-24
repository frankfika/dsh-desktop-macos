using System.Diagnostics;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace DSHDesktop.Windows;

internal sealed class MainForm : Form
{
    private readonly DshRuntimeManager _runtime = new();
    private readonly ToolStripLabel _statusDot = new("●");
    private readonly ToolStripLabel _statusText = new("Stopped");
    private readonly ToolStripLabel _addressText = new("http://127.0.0.1:3080");
    private readonly ToolStripButton _startButton = new("Start");
    private readonly ToolStripButton _stopButton = new("Stop");
    private readonly ToolStripButton _restartButton = new("Restart");
    private readonly ToolStripButton _browserButton = new("Open in browser");
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill };
    private readonly TableLayoutPanel _onboarding = new()
    {
        Dock = DockStyle.Fill,
        ColumnCount = 1,
        RowCount = 6,
        BackColor = SystemColors.Window,
    };
    private readonly Label _onboardingTitle = new()
    {
        Text = "DSH service is not running",
        AutoSize = true,
        Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 16, FontStyle.Bold),
        Anchor = AnchorStyles.None,
    };
    private readonly Label _onboardingMessage = new()
    {
        Text = "Checking the local runtime…",
        AutoSize = true,
        MaximumSize = new Size(620, 0),
        TextAlign = ContentAlignment.MiddleCenter,
        Anchor = AnchorStyles.None,
    };
    private readonly ProgressBar _progress = new()
    {
        Style = ProgressBarStyle.Marquee,
        MarqueeAnimationSpeed = 35,
        Width = 260,
        Visible = false,
        Anchor = AnchorStyles.None,
    };
    private readonly Button _primaryButton = new()
    {
        Text = "Install official DSH runtime",
        AutoSize = true,
        Padding = new Padding(14, 7, 14, 7),
        Anchor = AnchorStyles.None,
    };
    private readonly LinkLabel _nodeLink = new()
    {
        Text = "Node.js 22.19+ or 24+ is required — download Node.js",
        AutoSize = true,
        Anchor = AnchorStyles.None,
    };
    private readonly TextBox _logs = new()
    {
        Dock = DockStyle.Fill,
        Multiline = true,
        ReadOnly = true,
        ScrollBars = ScrollBars.Vertical,
        BackColor = Color.FromArgb(25, 25, 25),
        ForeColor = Color.Gainsboro,
        Font = new Font("Consolas", 9),
        WordWrap = false,
    };
    private bool _webViewReady;
    private string? _webViewError;

    public MainForm()
    {
        Text = "DSH Desktop";
        MinimumSize = new Size(960, 680);
        StartPosition = FormStartPosition.CenterScreen;
        Width = 1240;
        Height = 820;

        var toolbar = BuildToolbar();
        var content = new Panel { Dock = DockStyle.Fill };
        ConfigureOnboarding();
        content.Controls.Add(_webView);
        content.Controls.Add(_onboarding);

        var mainSplit = new SplitContainer
        {
            Dock = DockStyle.Fill,
            Orientation = Orientation.Horizontal,
            FixedPanel = FixedPanel.Panel2,
            Panel2MinSize = 110,
        };
        mainSplit.Panel1.Controls.Add(content);
        mainSplit.Panel2.Controls.Add(_logs);

        Controls.Add(mainSplit);
        Controls.Add(toolbar);

        Load += (_, _) => mainSplit.SplitterDistance = Math.Max(300, mainSplit.Height - 170);

        _runtime.StateChanged += state => OnUi(() => ApplyState(state));
        _runtime.LogReceived += line => OnUi(() => AppendLog(line));
        _primaryButton.Click += async (_, _) => await RunPrimaryActionAsync();
        _nodeLink.LinkClicked += (_, _) => OpenExternal("https://nodejs.org/");
        _startButton.Click += async (_, _) => await RunSafelyAsync(_runtime.StartAsync);
        _stopButton.Click += async (_, _) => await RunSafelyAsync(_runtime.StopAsync);
        _restartButton.Click += async (_, _) => await RunSafelyAsync(_runtime.RestartAsync);
        _browserButton.Click += (_, _) => OpenExternal(_runtime.ServiceUri.AbsoluteUri);

        Shown += async (_, _) =>
        {
            await InitializeWebViewAsync();
            await RunSafelyAsync(_runtime.InitializeAsync);
        };
        FormClosed += (_, _) => _runtime.Dispose();
    }

    private ToolStrip BuildToolbar()
    {
        var toolbar = new ToolStrip
        {
            Dock = DockStyle.Top,
            GripStyle = ToolStripGripStyle.Hidden,
            Padding = new Padding(8, 6, 8, 6),
            ImageScalingSize = new Size(18, 18),
        };
        _statusDot.ForeColor = Color.Gray;
        _statusDot.Font = new Font(SystemFonts.MessageBoxFont.FontFamily, 12, FontStyle.Bold);
        _addressText.ForeColor = SystemColors.GrayText;
        toolbar.Items.AddRange(new ToolStripItem[]
        {
            _statusDot,
            _statusText,
            new ToolStripSeparator(),
            _addressText,
            new ToolStripSeparator(),
            _startButton,
            _stopButton,
            _restartButton,
            _browserButton,
        });
        return toolbar;
    }

    private void ConfigureOnboarding()
    {
        _onboarding.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.Percent, 40));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        _onboarding.RowStyles.Add(new RowStyle(SizeType.Percent, 60));
        _onboarding.Controls.Add(new Panel(), 0, 0);
        _onboarding.Controls.Add(_onboardingTitle, 0, 1);
        _onboarding.Controls.Add(_onboardingMessage, 0, 2);
        _onboarding.Controls.Add(_progress, 0, 3);
        _onboarding.Controls.Add(_primaryButton, 0, 4);
        _onboarding.Controls.Add(_nodeLink, 0, 5);
        _webView.Visible = false;
    }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            _ = CoreWebView2Environment.GetAvailableBrowserVersionString();
            await _webView.EnsureCoreWebView2Async();
            _webView.CoreWebView2.NewWindowRequested += (_, args) =>
            {
                args.Handled = true;
                OpenExternal(args.Uri);
            };
            _webViewReady = true;
        }
        catch (WebView2RuntimeNotFoundException)
        {
            _webViewError = "Microsoft Edge WebView2 Runtime is missing. Install Microsoft Edge/WebView2 and restart.";
            AppendLog(_webViewError);
        }
        catch (Exception ex)
        {
            _webViewError = $"WebView2 initialization failed: {ex.Message}";
            AppendLog(_webViewError);
        }
    }

    private void ApplyState(RuntimeState state)
    {
        _statusText.Text = state.Message;
        _statusDot.ForeColor = state.Status switch
        {
            RuntimeStatus.Running or RuntimeStatus.ExternalRunning => Color.SeaGreen,
            RuntimeStatus.Starting or RuntimeStatus.Installing or RuntimeStatus.Stopping => Color.DarkOrange,
            RuntimeStatus.Failed => Color.Firebrick,
            _ => Color.Gray,
        };

        _startButton.Enabled = state.Status is RuntimeStatus.Stopped or RuntimeStatus.Failed
            && _runtime.DshScriptPath is not null;
        _stopButton.Enabled = state.OwnsProcess && state.Status != RuntimeStatus.Stopping;
        _restartButton.Enabled = state.Status == RuntimeStatus.Running;
        _browserButton.Enabled = state.WebReady;
        _progress.Visible = state.Status is RuntimeStatus.Installing or RuntimeStatus.Starting;

        if (state.WebReady && _webViewReady)
        {
            _onboarding.Visible = false;
            _webView.Visible = true;
            if (_webView.Source != _runtime.ServiceUri)
            {
                _webView.Source = _runtime.ServiceUri;
            }
            return;
        }

        _webView.Visible = false;
        _onboarding.Visible = true;
        _onboarding.BringToFront();
        _onboardingTitle.Text = state.Status switch
        {
            RuntimeStatus.Installing => "Installing DeepSeek Harness",
            RuntimeStatus.Starting => "Starting DSH service",
            RuntimeStatus.Failed => "DSH needs attention",
            _ => "DSH service is not running",
        };
        _onboardingMessage.Text = _webViewError ?? state.Message;

        var dshInstalled = _runtime.DshScriptPath is not null;
        _primaryButton.Text = dshInstalled ? "Start DSH service" : "Install official DSH runtime";
        _primaryButton.Enabled = state.Status is RuntimeStatus.Stopped or RuntimeStatus.Failed;
        _primaryButton.Visible = state.Status is not RuntimeStatus.Installing and not RuntimeStatus.Starting;
        _nodeLink.Visible = !_runtime.NodeAvailable;
    }

    private async Task RunPrimaryActionAsync()
    {
        if (_runtime.DshScriptPath is null)
        {
            await RunSafelyAsync(_runtime.InstallOfficialRuntimeAsync);
        }
        else
        {
            await RunSafelyAsync(_runtime.StartAsync);
        }
    }

    private async Task RunSafelyAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            AppendLog($"Unexpected error: {ex}");
            MessageBox.Show(this, ex.Message, "DSH Desktop", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void AppendLog(string line)
    {
        if (_logs.TextLength > 200_000)
        {
            _logs.Text = _logs.Text[^100_000..];
        }
        _logs.AppendText(line + Environment.NewLine);
        _logs.SelectionStart = _logs.TextLength;
        _logs.ScrollToCaret();
    }

    private void OnUi(Action action)
    {
        if (IsDisposed)
        {
            return;
        }
        if (InvokeRequired)
        {
            BeginInvoke(action);
        }
        else
        {
            action();
        }
    }

    private static void OpenExternal(string url)
    {
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
    }
}
