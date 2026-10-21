using System.Diagnostics;
using System.IO;
using Amberflow.Application;
using Amberflow.Core.Actions;

namespace Amberflow.Windows.Actions;

public sealed class OpenActionHandler : IActionHandler
{
    public ActionId Action => ActionId.Float;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        foreach (var path in request.Paths)
        {
            Process.Start(new ProcessStartInfo(Path.GetFullPath(path)) { UseShellExecute = true });
        }

        return Task.CompletedTask;
    }
}
