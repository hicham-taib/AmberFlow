namespace Amberflow.Core.Files;

public static class UniquePathPolicy
{
    public static string Resolve(string requestedPath, Func<string, bool> exists)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestedPath);
        ArgumentNullException.ThrowIfNull(exists);

        if (!exists(requestedPath))
        {
            return requestedPath;
        }

        var directory = Path.GetDirectoryName(requestedPath) ?? string.Empty;
        var extension = Path.GetExtension(requestedPath);
        var stem = Path.GetFileNameWithoutExtension(requestedPath);

        for (var index = 2; ; index++)
        {
            var candidate = Path.Combine(directory, $"{stem} {index}{extension}");
            if (!exists(candidate))
            {
                return candidate;
            }
        }
    }
}
