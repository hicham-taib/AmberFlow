using Amberflow.Application;
using Amberflow.Core.Actions;
using Amberflow.Core.Files;
using Forms = System.Windows.Forms;

namespace Amberflow.Windows.Actions;

public sealed class MoveActionHandler(IUserNotifier notifier) : IActionHandler
{
    public ActionId Action => ActionId.Move;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        using var picker = new Forms.FolderBrowserDialog
        {
            Description = "Move selected items to…",
            UseDescriptionForTitle = true,
            ShowNewFolderButton = true,
        };

        if (picker.ShowDialog() != Forms.DialogResult.OK)
        {
            return Task.CompletedTask;
        }

        var destinationDirectory = Path.GetFullPath(picker.SelectedPath);
        var completed = new List<(string Source, string Destination, bool IsDirectory)>();

        try
        {
            foreach (var sourceValue in request.Paths)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var source = Path.GetFullPath(sourceValue);
                var isDirectory = Directory.Exists(source);
                if (!isDirectory && !File.Exists(source))
                {
                    throw new FileNotFoundException("A selected item no longer exists.", source);
                }

                EnsureDirectoryIsNotMovedInsideItself(source, destinationDirectory, isDirectory);
                var requestedDestination = Path.Combine(destinationDirectory, Path.GetFileName(source));
                if (string.Equals(source, requestedDestination, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var destination = UniquePathPolicy.Resolve(
                    requestedDestination,
                    path => File.Exists(path) || Directory.Exists(path));

                if (isDirectory)
                {
                    Directory.Move(source, destination);
                }
                else
                {
                    File.Move(source, destination);
                }

                completed.Add((source, destination, isDirectory));
            }
        }
        catch
        {
            RollBack(completed);
            throw;
        }

        notifier.ShowInformation($"Moved {completed.Count} item{(completed.Count == 1 ? string.Empty : "s")}.");
        return Task.CompletedTask;
    }

    private static void EnsureDirectoryIsNotMovedInsideItself(string source, string destination, bool isDirectory)
    {
        if (!isDirectory)
        {
            return;
        }

        var sourcePrefix = Path.TrimEndingDirectorySeparator(source) + Path.DirectorySeparatorChar;
        var destinationPrefix = Path.TrimEndingDirectorySeparator(destination) + Path.DirectorySeparatorChar;
        if (destinationPrefix.StartsWith(sourcePrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new IOException("A folder cannot be moved inside itself.");
        }
    }

    private static void RollBack(IEnumerable<(string Source, string Destination, bool IsDirectory)> completed)
    {
        foreach (var move in completed.Reverse())
        {
            try
            {
                if (move.IsDirectory && Directory.Exists(move.Destination) && !Directory.Exists(move.Source))
                {
                    Directory.Move(move.Destination, move.Source);
                }
                else if (!move.IsDirectory && File.Exists(move.Destination) && !File.Exists(move.Source))
                {
                    File.Move(move.Destination, move.Source);
                }
            }
            catch (IOException)
            {
                // Preserve the original failure. Any remaining destination is left intact.
            }
        }
    }
}
