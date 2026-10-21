namespace Amberflow.Application;

public interface IUserNotifier
{
    void ShowInformation(string message);

    void ShowError(string message);
}
