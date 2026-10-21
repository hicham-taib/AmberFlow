namespace Amberflow.Application;

public sealed class ActionDispatcher(IEnumerable<IActionHandler> handlers, IUserNotifier notifier)
{
    private readonly IReadOnlyDictionary<Core.Actions.ActionId, IActionHandler> _handlers =
        handlers.ToDictionary(handler => handler.Action);

    public async Task DispatchAsync(ActionRequest request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.Paths.Count == 0)
        {
            notifier.ShowError("Drop at least one file or folder.");
            return;
        }

        if (!_handlers.TryGetValue(request.Action, out var handler))
        {
            notifier.ShowInformation("This action is part of the Windows roadmap and is not available yet.");
            return;
        }

        try
        {
            await handler.ExecuteAsync(request, cancellationToken).ConfigureAwait(true);
        }
        catch (Exception exception)
        {
            notifier.ShowError(exception.Message);
        }
    }
}
