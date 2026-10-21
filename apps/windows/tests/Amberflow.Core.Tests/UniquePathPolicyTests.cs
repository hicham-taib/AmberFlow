using Amberflow.Core.Files;
using Xunit;

namespace Amberflow.Core.Tests;

public sealed class UniquePathPolicyTests
{
    [Fact]
    public void ReturnsTheRequestedPathWhenItIsAvailable()
    {
        var requested = Path.Combine("root", "Files", "report.pdf");
        var result = UniquePathPolicy.Resolve(requested, _ => false);

        Assert.Equal(requested, result);
    }

    [Fact]
    public void AddsAStableNumericSuffixWithoutChangingTheExtension()
    {
        var requested = Path.Combine("root", "Files", "report.pdf");
        var second = Path.Combine("root", "Files", "report 2.pdf");
        var third = Path.Combine("root", "Files", "report 3.pdf");
        var occupied = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            requested,
            second,
        };

        var result = UniquePathPolicy.Resolve(requested, occupied.Contains);

        Assert.Equal(third, result);
    }
}
