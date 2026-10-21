using Amberflow.Core.Geometry;
using Xunit;

namespace Amberflow.Core.Tests;

public sealed class RadialHitTesterTests
{
    private readonly RadialHitTester _subject = new(50, 100);

    [Theory]
    [InlineData(0, -75, 0)]
    [InlineData(75, 0, 1)]
    [InlineData(0, 75, 2)]
    [InlineData(-75, 0, 3)]
    public void MapsClockwiseQuadrantsFromTheTop(double x, double y, int expected)
    {
        Assert.Equal(expected, _subject.HitTest(x, y, 4));
    }

    [Theory]
    [InlineData(0, 0)]
    [InlineData(20, 20)]
    [InlineData(101, 0)]
    public void RejectsTheCenterAndOutside(double x, double y)
    {
        Assert.Null(_subject.HitTest(x, y, 4));
    }
}
