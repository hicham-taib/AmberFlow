namespace Amberflow.Core.Geometry;

public sealed class RadialHitTester(double innerRadius, double outerRadius)
{
    public int? HitTest(double x, double y, int itemCount)
    {
        if (itemCount <= 0)
        {
            return null;
        }

        var radius = Math.Sqrt((x * x) + (y * y));
        if (radius < innerRadius || radius > outerRadius)
        {
            return null;
        }

        var degrees = (Math.Atan2(y, x) * 180 / Math.PI + 450) % 360;
        var slice = 360d / itemCount;
        return (int)(degrees / slice);
    }
}
