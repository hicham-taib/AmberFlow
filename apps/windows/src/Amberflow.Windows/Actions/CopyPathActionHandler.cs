using System.Windows;
using Amberflow.Application;
using Amberflow.Core.Actions;

namespace Amberflow.Windows.Actions;

public sealed class CopyPathActionHandler : IActionHandler
{
    public ActionId Action => ActionId.CopyPath;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        EnsurePathsExist(request.Paths);
        Clipboard.SetText(string.Join(Environment.NewLine, request.Paths.Select(Path.GetFullPath)));
        return Task.CompletedTask;
    }

    private static void EnsurePathsExist(IEnumerable<string> paths)
    {
        var missing = paths.FirstOrDefault(path => !File.Exists(path) && !Directory.Exists(path));
        if (missing is not null)
        {
            throw new FileNotFoundException("A selected item no longer exists.", missing);
        }
    }
}
