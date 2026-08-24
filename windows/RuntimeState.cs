namespace DSHDesktop.Windows;

internal enum RuntimeStatus
{
    Stopped,
    Installing,
    Starting,
    Running,
    ExternalRunning,
    Stopping,
    Failed,
}

internal sealed record RuntimeState(RuntimeStatus Status, string Message)
{
    public bool WebReady => Status is RuntimeStatus.Running or RuntimeStatus.ExternalRunning;
    public bool OwnsProcess => Status is RuntimeStatus.Running or RuntimeStatus.Starting or RuntimeStatus.Stopping;
}
