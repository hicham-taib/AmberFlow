using Amberflow.Core.Actions;
using Xunit;

namespace Amberflow.Core.Tests;

public sealed class ActionCatalogTests
{
    [Theory]
    [InlineData(RadialMode.Tools, 7)]
    [InlineData(RadialMode.Actions, 6)]
    [InlineData(RadialMode.Convert, 8)]
    public void EveryPaletteHasTheExpectedActions(RadialMode mode, int count)
    {
        var actions = ActionCatalog.For(mode);

        Assert.Equal(count, actions.Count);
        Assert.Equal(count, actions.Select(action => action.Id).Distinct().Count());
        Assert.DoesNotContain(actions, action => string.IsNullOrWhiteSpace(action.Label));
    }
}
