using System.Windows;
using Amberflow.Application;
using Amberflow.Windows.Actions;
using Amberflow.Windows.Gestures;
using Amberflow.Windows.Shell;
using Amberflow.Windows.UI;

namespace Amberflow.Windows;

public partial class App
{
    private GestureMonitor? _gestureMonitor;
    private TrayIconService? _trayIcon;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var notifier = new WpfNotifier();
        IActionHandler[] handlers =
        [
            new CopyPathActionHandler(),
            new CopyFilesActionHandler(),
            new MoveActionHandler(notifier),
            new OpenActionHandler(),
            new TerminalActionHandler(),
            new ZipActionHandler(notifier),
        ];

        var dispatcher = new ActionDispatcher(handlers, notifier);
        var radialWindow = new RadialMenuWindow(dispatcher);

        _gestureMonitor = new GestureMonitor(radialWindow);
        _gestureMonitor.Start();

        _trayIcon = new TrayIconService();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _gestureMonitor?.Dispose();
        _trayIcon?.Dispose();
        base.OnExit(e);
    }
}
