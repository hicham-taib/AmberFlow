using System.Windows;
using Amberflow.Application;

namespace Amberflow.Windows.Shell;

public sealed class WpfNotifier : IUserNotifier
{
    public void ShowInformation(string message) =>
        MessageBox.Show(message, "Amberflow", MessageBoxButton.OK, MessageBoxImage.Information);

    public void ShowError(string message) =>
        MessageBox.Show(message, "Amberflow", MessageBoxButton.OK, MessageBoxImage.Error);
}
