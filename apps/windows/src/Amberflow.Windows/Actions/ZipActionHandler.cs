using System.IO.Compression;
using Amberflow.Application;
using Amberflow.Core.Actions;
using Amberflow.Core.Files;

namespace Amberflow.Windows.Actions;

public sealed class ZipActionHandler(IUserNotifier notifier) : IActionHandler
{
    public ActionId Action => ActionId.ConvertZip;

    public Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        var first = Path.GetFullPath(request.Paths[0]);
        var parent = Directory.Exists(first)
            ? Directory.GetParent(Path.TrimEndingDirectorySeparator(first))?.FullName
            : Path.GetDirectoryName(first);

        if (parent is null)
        {
            throw new DirectoryNotFoundException("A destination folder could not be determined.");
        }

        var stem = Path.GetFileNameWithoutExtension(Path.TrimEndingDirectorySeparator(first));
        var output = UniquePathPolicy.Resolve(
            Path.Combine(parent, $"{stem}.zip"),
            path => File.Exists(path) || Directory.Exists(path));

        using (var archive = ZipFile.Open(output, ZipArchiveMode.Create))
        {
            var usedEntries = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var pathValue in request.Paths)
            {
                cancellationToken.ThrowIfCancellationRequested();
                AddPath(archive, Path.GetFullPath(pathValue), usedEntries);
            }
        }

        notifier.ShowInformation($"Created {Path.GetFileName(output)}");
        return Task.CompletedTask;
    }

    private static void AddPath(ZipArchive archive, string path, ISet<string> usedEntries)
    {
        if (File.Exists(path))
        {
            var entry = UniqueEntry(Path.GetFileName(path), usedEntries);
            archive.CreateEntryFromFile(path, entry, CompressionLevel.Optimal);
            return;
        }

        if (!Directory.Exists(path))
        {
            throw new FileNotFoundException("A selected item no longer exists.", path);
        }

        var root = Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(path)) ?? path;
        foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(root, file).Replace('\\', '/');
            archive.CreateEntryFromFile(file, UniqueEntry(relative, usedEntries), CompressionLevel.Optimal);
        }
    }

    private static string UniqueEntry(string requested, ISet<string> usedEntries)
    {
        if (usedEntries.Add(requested))
        {
            return requested;
        }

        var directory = Path.GetDirectoryName(requested)?.Replace('\\', '/');
        var extension = Path.GetExtension(requested);
        var stem = Path.GetFileNameWithoutExtension(requested);
        for (var index = 2; ; index++)
        {
            var fileName = $"{stem} {index}{extension}";
            var candidate = string.IsNullOrEmpty(directory) ? fileName : $"{directory}/{fileName}";
            if (usedEntries.Add(candidate))
            {
                return candidate;
            }
        }
    }
}
