using Amberflow.Core.Actions;

namespace Amberflow.Application;

public sealed record ActionRequest(ActionId Action, IReadOnlyList<string> Paths);
