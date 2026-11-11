using System.Text.Json.Serialization;

namespace Presenter.Windows.Core;

// The engine's state, as BridgeState.swift writes it. Property names match the JSON, ignoring case.

public sealed class EngineState
{
    public string ProjectName { get; set; } = "";
    /// <summary>Goes up each time the project changes.</summary>
    public int ProjectRevision { get; set; }
    /// <summary>A load or save problem for the operator to read.</summary>
    public string? Problem { get; set; }
    public List<ShowInfo> Shows { get; set; } = [];
    public Guid ActiveShowID { get; set; }
    public List<ItemInfo> Items { get; set; } = [];
    public Guid? SelectedItemID { get; set; }
    public List<LibraryEntry> Library { get; set; } = [];
    /// <summary>The selected item's slides, in the order they play.</summary>
    public List<SlideEntry> Slides { get; set; } = [];
    public SlidePosition? Cued { get; set; }
    public SlidePosition? Live { get; set; }
    /// <summary>What the audience sees. Null while blacked out.</summary>
    public SlideModel? Audience { get; set; }
    public bool IsBlackout { get; set; }
    public bool CanRestore { get; set; }
    public string? Credits { get; set; }
    public string? UndoName { get; set; }
    public string? RedoName { get; set; }

    /// <summary>The audience output's content as text, to tell when it changes. Set by <see cref="Engine.State"/>.</summary>
    [JsonIgnore]
    public string AudienceKey { get; set; } = "";
}

public sealed class ShowInfo
{
    public Guid ID { get; set; }
    public string Title { get; set; } = "";
}

public sealed class ItemInfo
{
    public Guid ID { get; set; }
    public Guid PresentationID { get; set; }
    public string Title { get; set; } = "";
    /// <summary>"presentation", "song" or "bible".</summary>
    public string Kind { get; set; } = "";
    public int SlideCount { get; set; }
}

public sealed class LibraryEntry
{
    public Guid ID { get; set; }
    public string Title { get; set; } = "";
    public string Kind { get; set; } = "";
    public int SlideCount { get; set; }
}

public sealed record SlidePosition
{
    public Guid ItemID { get; set; }
    public Guid SlideID { get; set; }
    public int Occurrence { get; set; }
}

public sealed class SlideEntry
{
    public SlidePosition Position { get; set; } = new();
    public string? Label { get; set; }
    /// <summary>"verse", "chorus", "bridge"… for the label's colour.</summary>
    public string? Section { get; set; }
    public SlideModel Slide { get; set; } = new();
}

/// <summary>A slide ready to draw on the 1920×1080 canvas: a background, then elements bottom to top.</summary>
public sealed class SlideModel
{
    public BackgroundModel Background { get; set; } = new();
    public List<ElementModel> Elements { get; set; } = [];
}

public sealed class BackgroundModel
{
    /// <summary>"default", "color", "image", "video" or "transparent".</summary>
    public string Kind { get; set; } = "default";
    public RGBA? Color { get; set; }
    public string? Path { get; set; }
    /// <summary>"fill", "fit" or "stretch".</summary>
    public string? Scaling { get; set; }
    public double? Dimming { get; set; }
}

public sealed class ElementModel
{
    /// <summary>"text", "shape" or "image".</summary>
    public string Kind { get; set; } = "";
    /// <summary>Where it sits, in 0…1 of the canvas. Null for text in the centred flow.</summary>
    public Frame? Frame { get; set; }
    public string? Text { get; set; }
    /// <summary>"top", "center" or "bottom".</summary>
    public string? VerticalAlignment { get; set; }
    public TextStyleModel? Style { get; set; }
    /// <summary>"rectangle", "roundedRectangle" or "ellipse".</summary>
    public string? Shape { get; set; }
    public RGBA? Fill { get; set; }
    public RGBA? Stroke { get; set; }
    public double StrokeWidth { get; set; }
    public double CornerRadius { get; set; }
    public string? Path { get; set; }
    public string? Scaling { get; set; }
    public double Opacity { get; set; } = 1;
}

public sealed class Frame
{
    public double X { get; set; }
    public double Y { get; set; }
    public double Width { get; set; }
    public double Height { get; set; }
}

public sealed class TextStyleModel
{
    public string? FontFamily { get; set; }
    public double FontSize { get; set; } = 96;
    /// <summary>"regular", "medium", "semibold", "bold" or "heavy".</summary>
    public string Weight { get; set; } = "semibold";
    public bool IsItalic { get; set; }
    public RGBA Color { get; set; } = RGBA.White;
    /// <summary>"leading", "center" or "trailing".</summary>
    public string Alignment { get; set; } = "center";
    public double LineSpacing { get; set; }
    public bool HasShadow { get; set; } = true;
    public OutlineModel? Outline { get; set; }
    public BackgroundBoxModel? BackgroundBox { get; set; }
}

public sealed class OutlineModel
{
    public RGBA Color { get; set; } = RGBA.Black;
    public double Width { get; set; } = 4;
}

public sealed class BackgroundBoxModel
{
    public RGBA Color { get; set; } = new() { Alpha = 0.6 };
    public double Padding { get; set; } = 24;
    public double CornerRadius { get; set; } = 12;
}

/// <summary>An sRGB colour, components 0…1.</summary>
public sealed class RGBA
{
    public double Red { get; set; }
    public double Green { get; set; }
    public double Blue { get; set; }
    public double Alpha { get; set; } = 1;

    public static RGBA White => new() { Red = 1, Green = 1, Blue = 1 };
    public static RGBA Black => new();
}
