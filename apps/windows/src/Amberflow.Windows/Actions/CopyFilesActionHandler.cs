using System.Collections.Specialized;
using System.Windows;
using Amberflow.Application;
using Amberflow.Core.Actions;
using Clipboard = System.Windows.Clipboard;

namespace Amberflow.Windows.Actions;

public sealed class CopyFilesActionHandler : IActionHandler
{
    public ActionId Action => ActionId.Copy;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        var paths = request.Paths.Select(Path.GetFullPath).ToArray();
        var missing = paths.FirstOrDefault(path => !File.Exists(path) && !Directory.Exists(path));
        if (missing is not null)
        {
            throw new FileNotFoundException("A selected item no longer exists.", missing);
        }

        var files = new StringCollection();
        files.AddRange(paths);
        Clipboard.SetFileDropList(files);
        return Task.CompletedTask;
    }
}
