using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using Amberflow.Application;
using Amberflow.Core.Actions;

namespace Amberflow.Windows.Actions;

public sealed class TerminalActionHandler : IActionHandler
{
    public ActionId Action => ActionId.Terminal;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        var selected = Path.GetFullPath(request.Paths[0]);
        var directory = Directory.Exists(selected) ? selected : Path.GetDirectoryName(selected);
        if (directory is null || !Directory.Exists(directory))
        {
            throw new DirectoryNotFoundException("The selected item's containing folder is unavailable.");
        }

        try
        {
            var terminal = new ProcessStartInfo("wt.exe") { UseShellExecute = true };
            terminal.ArgumentList.Add("-d");
            terminal.ArgumentList.Add(directory);
            Process.Start(terminal);
        }
        catch (Win32Exception)
        {
            Process.Start(new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = true,
                WorkingDirectory = directory,
            });
        }

        return Task.CompletedTask;
    }
}
