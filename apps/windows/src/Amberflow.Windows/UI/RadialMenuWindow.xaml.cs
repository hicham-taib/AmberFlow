using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Amberflow.Application;
using Amberflow.Core.Actions;

namespace Amberflow.Windows.UI;

public partial class RadialMenuWindow
{
    private readonly ActionDispatcher _dispatcher;
    private readonly DispatcherTimer _dismissTimer;

    public RadialMenuWindow(ActionDispatcher dispatcher)
    {
        _dispatcher = dispatcher;
        InitializeComponent();
        _dismissTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        _dismissTimer.Tick += (_, _) => HideWheel();
        DragOver += OnDragOver;
        DragLeave += OnDragLeave;
        Drop += OnDrop;
        PreviewKeyDown += (_, args) =>
        {
            if (args.Key == Key.Escape)
            {
                HideWheel();
            }
        };
    }

    public void ShowAt(RadialMode mode, Point screenPosition)
    {
        _dismissTimer.Stop();
        Menu.SetPalette(mode, ActionCatalog.For(mode));

        var dpi = VisualTreeHelper.GetDpi(this);
        Left = (screenPosition.X / dpi.DpiScaleX) - (Width / 2);
        Top = (screenPosition.Y / dpi.DpiScaleY) - (Height / 2);

        if (!IsVisible)
        {
            Show();
        }
    }

    public void SetMode(RadialMode mode)
    {
        _dismissTimer.Stop();
        Menu.SetPalette(mode, ActionCatalog.For(mode));
    }

    public void ScheduleDismiss()
    {
        _dismissTimer.Stop();
        _dismissTimer.Start();
    }

    public void HideWheel()
    {
        _dismissTimer.Stop();
        Menu.ClearHighlight();
        Hide();
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            e.Effects = DragDropEffects.None;
            e.Handled = true;
            return;
        }

        var action = Menu.HighlightAt(e.GetPosition(Menu));
        e.Effects = action is null ? DragDropEffects.None : DragDropEffects.Link;
        e.Handled = true;
    }

    private void OnDragLeave(object sender, DragEventArgs e) => Menu.ClearHighlight();

    private async void OnDrop(object sender, DragEventArgs e)
    {
        try
        {
            if (e.Data.GetData(DataFormats.FileDrop) is not string[] paths)
            {
                return;
            }

            var action = Menu.ActionAt(e.GetPosition(Menu));
            if (action is not null)
            {
                await _dispatcher.DispatchAsync(new ActionRequest(action.Id, paths));
            }
        }
        finally
        {
            HideWheel();
        }
    }
}
