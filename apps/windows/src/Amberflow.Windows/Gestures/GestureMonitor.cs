using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
using Amberflow.Core.Actions;
using Amberflow.Windows.UI;

namespace Amberflow.Windows.Gestures;

public sealed class GestureMonitor : IDisposable
{
    private const int LeftButton = 0x01;
    private const int ShiftKey = 0x10;
    private const int ControlKey = 0x11;
    private const int AltKey = 0x12;
    private const int DragWidth = 68;
    private const int DragHeight = 69;

    private readonly RadialMenuWindow _window;
    private readonly DispatcherTimer _timer;
    private NativePoint _mouseDownPoint;
    private bool _wasMouseDown;
    private bool _hasMoved;
    private RadialMode? _visibleMode;

    public GestureMonitor(RadialMenuWindow window)
    {
        _window = window;
        _timer = new DispatcherTimer(DispatcherPriority.Input)
        {
            Interval = TimeSpan.FromMilliseconds(32),
        };
        _timer.Tick += OnTick;
    }

    public void Start() => _timer.Start();

    public void Dispose()
    {
        _timer.Stop();
        _timer.Tick -= OnTick;
    }

    private void OnTick(object? sender, EventArgs e)
    {
        var mouseDown = IsPressed(LeftButton);
        GetCursorPos(out var cursor);

        if (!mouseDown)
        {
            Reset();
            return;
        }

        if (!_wasMouseDown)
        {
            _wasMouseDown = true;
            _mouseDownPoint = cursor;
            _hasMoved = false;
        }

        var dragX = Math.Max(GetSystemMetrics(DragWidth), 4);
        var dragY = Math.Max(GetSystemMetrics(DragHeight), 4);
        _hasMoved |= Math.Abs(cursor.X - _mouseDownPoint.X) >= dragX ||
                     Math.Abs(cursor.Y - _mouseDownPoint.Y) >= dragY;

        var mode = CurrentMode();
        if (!_hasMoved || mode is null || (!IsExplorerForeground() && !_window.IsVisible))
        {
            if (_window.IsVisible && mode is null)
            {
                HideWindow();
            }

            return;
        }

        if (!_window.IsVisible)
        {
            _window.ShowAt(mode.Value, new Point(cursor.X, cursor.Y));
        }
        else if (_visibleMode != mode)
        {
            _window.SetMode(mode.Value);
        }

        _visibleMode = mode;
    }

    private void Reset()
    {
        if (_wasMouseDown && _window.IsVisible)
        {
            // Give the OLE Drop event time to run after the mouse button changes state.
            _window.ScheduleDismiss();
        }

        _wasMouseDown = false;
        _hasMoved = false;
        _visibleMode = null;
    }

    private void HideWindow()
    {
        if (_window.IsVisible)
        {
            _window.HideWheel();
        }

        _visibleMode = null;
    }

    private static RadialMode? CurrentMode()
    {
        if (IsPressed(AltKey))
        {
            return RadialMode.Tools;
        }

        if (IsPressed(ControlKey))
        {
            return RadialMode.Actions;
        }

        if (IsPressed(ShiftKey))
        {
            return RadialMode.Convert;
        }

        return null;
    }

    private static bool IsExplorerForeground()
    {
        try
        {
            var window = GetForegroundWindow();
            _ = GetWindowThreadProcessId(window, out var processId);
            return processId != 0 &&
                   string.Equals(Process.GetProcessById((int)processId).ProcessName, "explorer", StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static bool IsPressed(int virtualKey) => (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll")]
    private static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint window, out uint processId);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        public int X;
        public int Y;
    }
}
