using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;
using MessageBox = System.Windows.MessageBox;

namespace Amberflow.Windows.Shell;

public sealed class TrayIconService : IDisposable
{
    private readonly Forms.NotifyIcon _notifyIcon;

    public TrayIconService()
    {
        _notifyIcon = new Forms.NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Amberflow",
            Visible = true,
            ContextMenuStrip = BuildMenu(),
        };

        _notifyIcon.DoubleClick += (_, _) => ShowAbout();
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }

    private Forms.ContextMenuStrip BuildMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Amberflow is watching File Explorer", null, (_, _) => ShowAbout());
        menu.Items.Add("About Amberflow", null, (_, _) => ShowAbout());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => System.Windows.Application.Current.Shutdown());
        return menu;
    }

    private static void ShowAbout() =>
        MessageBox.Show(
            "Amberflow for Windows\n\nDrag a file in File Explorer, then hold Alt, Ctrl, or Shift to open the action wheel.",
            "About Amberflow",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
}
