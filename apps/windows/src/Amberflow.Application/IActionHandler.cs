using Amberflow.Core.Actions;

namespace Amberflow.Application;

public interface IActionHandler
{
    ActionId Action { get; }

    Task ExecuteAsync(ActionRequest request, CancellationToken cancellationToken = default);
}
