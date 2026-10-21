using System.Collections.ObjectModel;

namespace Amberflow.Core.Actions;

public static class ActionCatalog
{
    private static readonly IReadOnlyDictionary<RadialMode, IReadOnlyList<ActionDefinition>> Palettes =
        new ReadOnlyDictionary<RadialMode, IReadOnlyList<ActionDefinition>>(
            new Dictionary<RadialMode, IReadOnlyList<ActionDefinition>>
            {
                [RadialMode.Tools] =
                [
                    new(ActionId.Compress, "COMPRESS", "↘"),
                    new(ActionId.Metadata, "METADATA", "ⓘ"),
                    new(ActionId.Edit, "EDIT", "◐"),
                    new(ActionId.Annotate, "ANNOTATE", "✎"),
                    new(ActionId.AddBackground, "ADD BG", "▣"),
                    new(ActionId.Crop, "CROP", "⌗"),
                    new(ActionId.Redact, "REDACT", "●"),
                ],
                [RadialMode.Actions] =
                [
                    new(ActionId.Share, "SHARE", "↗"),
                    new(ActionId.Float, "PREVIEW", "◉"),
                    new(ActionId.Copy, "COPY", "▤"),
                    new(ActionId.Move, "MOVE", "→"),
                    new(ActionId.CopyPath, "COPY PATH", "≡"),
                    new(ActionId.Terminal, "TERMINAL", ">_"),
                ],
                [RadialMode.Convert] =
                [
                    new(ActionId.ConvertPng, "PNG", "↻"),
                    new(ActionId.ConvertJpg, "JPG", "↻"),
                    new(ActionId.ConvertHeic, "HEIC", "↻"),
                    new(ActionId.ConvertTiff, "TIFF", "↻"),
                    new(ActionId.ConvertPdf, "PDF", "↻"),
                    new(ActionId.ConvertText, "TXT", "↻"),
                    new(ActionId.ConvertMarkdown, "MD", "↻"),
                    new(ActionId.ConvertZip, "ZIP", "↻"),
                ],
            });

    public static IReadOnlyList<ActionDefinition> For(RadialMode mode) => Palettes[mode];
}
