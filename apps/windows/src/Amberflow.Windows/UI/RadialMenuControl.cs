using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Amberflow.Core.Actions;
using Amberflow.Core.Geometry;
using Brush = System.Windows.Media.Brush;
using Point = System.Windows.Point;

namespace Amberflow.Windows.UI;

public sealed class RadialMenuControl : FrameworkElement
{
    private const double InnerRadius = 66;
    private const double OuterRadius = 168;
    private readonly RadialHitTester _hitTester = new(InnerRadius, OuterRadius);
    private IReadOnlyList<ActionDefinition> _items = [];
    private RadialMode _mode;
    private int? _highlightedIndex;

    public void SetPalette(RadialMode mode, IReadOnlyList<ActionDefinition> items)
    {
        _mode = mode;
        _items = items;
        _highlightedIndex = null;
        InvalidateVisual();
    }

    public ActionDefinition? HighlightAt(Point point)
    {
        _highlightedIndex = IndexAt(point);
        InvalidateVisual();
        return _highlightedIndex is int index ? _items[index] : null;
    }

    public ActionDefinition? ActionAt(Point point)
    {
        var index = IndexAt(point);
        return index is int value ? _items[value] : null;
    }

    public void ClearHighlight()
    {
        _highlightedIndex = null;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext drawingContext)
    {
        base.OnRender(drawingContext);
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        drawingContext.DrawEllipse(
            new SolidColorBrush(Color.FromArgb(238, 22, 24, 29)),
            new Pen(new SolidColorBrush(Color.FromArgb(90, 255, 255, 255)), 1),
            center,
            OuterRadius + 4,
            OuterRadius + 4);

        if (_items.Count == 0)
        {
            return;
        }

        var sweep = 360d / _items.Count;
        for (var index = 0; index < _items.Count; index++)
        {
            var start = -90 + (index * sweep);
            var geometry = CreateSegment(center, start, sweep);
            var fill = index == _highlightedIndex
                ? Color.FromRgb(234, 129, 43)
                : Color.FromArgb(246, 43, 46, 55);

            drawingContext.DrawGeometry(
                new SolidColorBrush(fill),
                new Pen(new SolidColorBrush(Color.FromArgb(70, 255, 255, 255)), 1),
                geometry);

            DrawItem(drawingContext, center, _items[index], start + (sweep / 2));
        }

        drawingContext.DrawEllipse(
            new SolidColorBrush(Color.FromRgb(19, 21, 26)),
            new Pen(new SolidColorBrush(Color.FromRgb(234, 129, 43)), 2),
            center,
            InnerRadius - 3,
            InnerRadius - 3);

        DrawCenteredText(
            drawingContext,
            center,
            _mode.ToString().ToUpperInvariant(),
            13,
            FontWeights.SemiBold,
            Brushes.White);
    }

    private int? IndexAt(Point point)
    {
        if (_items.Count == 0)
        {
            return null;
        }

        return _hitTester.HitTest(
            point.X - (ActualWidth / 2),
            point.Y - (ActualHeight / 2),
            _items.Count);
    }

    private static Geometry CreateSegment(Point center, double startDegrees, double sweepDegrees)
    {
        var outerStart = PointAt(center, OuterRadius, startDegrees);
        var outerEnd = PointAt(center, OuterRadius, startDegrees + sweepDegrees);
        var innerEnd = PointAt(center, InnerRadius, startDegrees + sweepDegrees);
        var innerStart = PointAt(center, InnerRadius, startDegrees);

        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(innerStart, true, true);
            context.LineTo(outerStart, true, false);
            context.ArcTo(
                outerEnd,
                new Size(OuterRadius, OuterRadius),
                0,
                sweepDegrees > 180,
                SweepDirection.Clockwise,
                true,
                false);
            context.LineTo(innerEnd, true, false);
            context.ArcTo(
                innerStart,
                new Size(InnerRadius, InnerRadius),
                0,
                sweepDegrees > 180,
                SweepDirection.Counterclockwise,
                true,
                false);
        }

        geometry.Freeze();
        return geometry;
    }

    private static Point PointAt(Point center, double radius, double degrees)
    {
        var radians = degrees * Math.PI / 180;
        return new Point(
            center.X + (Math.Cos(radians) * radius),
            center.Y + (Math.Sin(radians) * radius));
    }

    private void DrawItem(
        DrawingContext drawingContext,
        Point center,
        ActionDefinition item,
        double angle)
    {
        var position = PointAt(center, (InnerRadius + OuterRadius) / 2, angle);
        DrawCenteredText(
            drawingContext,
            position,
            $"{item.Glyph}\n{item.Label}",
            11,
            FontWeights.SemiBold,
            Brushes.White);
    }

    private void DrawCenteredText(
        DrawingContext drawingContext,
        Point center,
        string value,
        double size,
        FontWeight weight,
        Brush brush)
    {
        var text = new FormattedText(
            value,
            CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI Variable, Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal),
            size,
            brush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip)
        {
            TextAlignment = TextAlignment.Center,
            MaxTextWidth = 94,
        };

        drawingContext.DrawText(text, new Point(center.X - (text.MaxTextWidth / 2), center.Y - (text.Height / 2)));
    }
}
