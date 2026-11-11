using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Presenter.Windows.Core;

namespace Presenter.Windows;

/// <summary>
/// Draws a slide on a fixed 1920×1080 canvas scaled to fit, as the Mac app's SlideRenderView does, so thumbnails,
/// the preview and the audience output lay text out alike. A null slide draws black (blackout).
/// </summary>
public sealed class SlideView : Viewbox
{
    public const double CanvasWidth = 1920;
    public const double CanvasHeight = 1080;

    /// <param name="thumbnail">Draws pictures from small copies, for the slide grid.</param>
    /// <param name="checkerboard">Shows a transparent background as a checkerboard (operator views) rather than black.</param>
    public SlideView(SlideModel? slide, string? credits = null, bool thumbnail = false, bool checkerboard = true)
    {
        Stretch = Stretch.Uniform;
        var canvas = new Canvas { Width = CanvasWidth, Height = CanvasHeight, ClipToBounds = true, Background = Brushes.Black };
        if (slide is not null)
        {
            canvas.Children.Add(FullCanvas(BackgroundLayer(slide.Background, thumbnail, checkerboard)));
            var flow = slide.Elements.Where(e => e.Kind == "text" && e.Frame is null).ToList();
            if (flow.Count > 0) canvas.Children.Add(FullCanvas(Flow(flow)));
            foreach (var element in slide.Elements)
            {
                if (element.Frame is not { } frame) continue;
                var control = Element(element, frame, thumbnail);
                control.Width = frame.Width * CanvasWidth;
                control.Height = frame.Height * CanvasHeight;
                Canvas.SetLeft(control, frame.X * CanvasWidth);
                Canvas.SetTop(control, frame.Y * CanvasHeight);
                canvas.Children.Add(control);
            }
            if (!string.IsNullOrEmpty(credits)) canvas.Children.Add(Credits(credits));
        }
        Child = canvas;
    }

    private static Control FullCanvas(Control control)
    {
        control.Width = CanvasWidth;
        control.Height = CanvasHeight;
        return control;
    }

    // MARK: Backgrounds

    private static Control BackgroundLayer(BackgroundModel background, bool thumbnail, bool checkerboard)
    {
        switch (background.Kind)
        {
            case "color":
                return new Border { Background = Brush(background.Color ?? RGBA.Black) };
            case "image" when Pictures.Load(background.Path, thumbnail) is { } picture:
                return Dimmed(new Image { Source = picture, Stretch = Scaling(background.Scaling) }, background.Dimming);
            case "video":
                // Videos don't play in this version: black, under the slide's words.
                return Dimmed(new Border(), background.Dimming);
            case "transparent":
                return checkerboard ? Checkerboard() : new Border();
            default:
                return DefaultBackground();
        }
    }

    /// <summary>The app's background when neither the slide nor its presentation sets one.</summary>
    public static Control DefaultBackground() => new Border
    {
        Background = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.FromRgb(15, 20, 41), 0),
                new GradientStop(Color.FromRgb(5, 5, 13), 1),
            },
        },
    };

    private static Control Dimmed(Control content, double? dimming) => new Panel
    {
        Background = Brushes.Black,
        ClipToBounds = true,
        Children = { content, new Border { Background = new SolidColorBrush(Colors.Black, dimming ?? 0) } },
    };

    private static Control Checkerboard()
    {
        const double square = 60;
        var board = new Canvas { Background = new SolidColorBrush(Color.FromRgb(209, 209, 209)) };
        var dark = new SolidColorBrush(Color.FromRgb(158, 158, 158));
        for (var row = 0; row < CanvasHeight / square; row++)
        {
            for (var column = 0; column < CanvasWidth / square; column++)
            {
                if ((row + column) % 2 != 0) continue;
                var cell = new Rectangle { Width = square, Height = square, Fill = dark };
                Canvas.SetLeft(cell, column * square);
                Canvas.SetTop(cell, row * square);
                board.Children.Add(cell);
            }
        }
        return board;
    }

    // MARK: Elements

    /// <summary>Text without a frame: centred and stacked, 120 points in from the edges, shrunk to fit if needed.</summary>
    private static Control Flow(List<ElementModel> texts)
    {
        var stack = new StackPanel { Spacing = 48 };
        foreach (var text in texts)
        {
            var styled = StyledText(text, CanvasWidth - 240);
            styled.HorizontalAlignment = HorizontalAlignment.Center;
            stack.Children.Add(styled);
        }
        return new Border
        {
            Padding = new Thickness(120),
            Child = new Viewbox { Stretch = Stretch.Uniform, StretchDirection = StretchDirection.DownOnly, Child = stack },
        };
    }

    private static Control Element(ElementModel element, Frame frame, bool thumbnail)
    {
        switch (element.Kind)
        {
            case "text":
                var style = element.Style ?? new TextStyleModel();
                return new Viewbox
                {
                    Stretch = Stretch.Uniform,
                    StretchDirection = StretchDirection.DownOnly,
                    HorizontalAlignment = style.Alignment switch
                    {
                        "leading" => HorizontalAlignment.Left,
                        "trailing" => HorizontalAlignment.Right,
                        _ => HorizontalAlignment.Center,
                    },
                    VerticalAlignment = element.VerticalAlignment switch
                    {
                        "top" => VerticalAlignment.Top,
                        "bottom" => VerticalAlignment.Bottom,
                        _ => VerticalAlignment.Center,
                    },
                    Child = StyledText(element, frame.Width * CanvasWidth),
                };
            case "shape":
                var fill = element.Fill is { } f ? Brush(f) : null;
                var stroke = element.Stroke is { } s && element.StrokeWidth > 0 ? Brush(s) : null;
                if (element.Shape == "ellipse")
                    return new Ellipse { Fill = fill, Stroke = stroke, StrokeThickness = stroke is null ? 0 : element.StrokeWidth };
                // A border's outline is drawn inside its bounds, as the Mac app draws shapes.
                return new Border
                {
                    Background = fill,
                    BorderBrush = stroke,
                    BorderThickness = new Thickness(stroke is null ? 0 : element.StrokeWidth),
                    CornerRadius = new CornerRadius(element.Shape == "roundedRectangle" ? element.CornerRadius : 0),
                };
            case "image":
                if (Pictures.Load(element.Path, thumbnail) is { } picture)
                {
                    return new Border
                    {
                        ClipToBounds = true,
                        Opacity = element.Opacity,
                        Child = new Image { Source = picture, Stretch = Scaling(element.Scaling) },
                    };
                }
                return new Border { Background = new SolidColorBrush(Colors.Gray, 0.35) };
            default:
                return new Border();
        }
    }

    /// <summary>Words in their style: font, colour, outline, shadow and the box behind them.</summary>
    private static Control StyledText(ElementModel element, double width)
    {
        var style = element.Style ?? new TextStyleModel();
        var padding = style.BackgroundBox?.Padding ?? 0;
        var textWidth = Math.Max(1, width - 2 * padding);

        TextBlock Letters(RGBA color)
        {
            var block = new TextBlock
            {
                Text = element.Text ?? "",
                FontFamily = Font(style.FontFamily),
                FontSize = Math.Max(1, style.FontSize),
                FontWeight = style.Weight switch
                {
                    "regular" => FontWeight.Normal,
                    "medium" => FontWeight.Medium,
                    "bold" => FontWeight.Bold,
                    "heavy" => FontWeight.Heavy,
                    _ => FontWeight.SemiBold,
                },
                FontStyle = style.IsItalic ? FontStyle.Italic : FontStyle.Normal,
                Foreground = Brush(color),
                TextAlignment = style.Alignment switch
                {
                    "leading" => TextAlignment.Left,
                    "trailing" => TextAlignment.Right,
                    _ => TextAlignment.Center,
                },
                TextWrapping = TextWrapping.Wrap,
                MaxWidth = textWidth,
            };
            if (style.LineSpacing != 0) block.LineHeight = style.FontSize * 1.2 + style.LineSpacing;
            return block;
        }

        var letters = new Grid();
        if (style.Outline is { Width: > 0 } outline)
        {
            // Copies of the words around the letters make the outline, as on the Mac.
            const int copies = 12;
            for (var index = 0; index < copies; index++)
            {
                var angle = index * 2 * Math.PI / copies;
                var copy = Letters(outline.Color);
                copy.RenderTransform = new TranslateTransform(Math.Cos(angle) * outline.Width, Math.Sin(angle) * outline.Width);
                letters.Children.Add(copy);
            }
        }
        letters.Children.Add(Letters(style.Color));
        if (style.HasShadow) letters.Effect = new DropShadowEffect { Color = Color.FromArgb(153, 0, 0, 0), BlurRadius = 12, OffsetX = 0, OffsetY = 3 };

        if (style.BackgroundBox is not { } box) return letters;
        return new Border
        {
            Background = Brush(box.Color),
            CornerRadius = new CornerRadius(box.CornerRadius),
            Padding = new Thickness(box.Padding),
            Child = letters,
        };
    }

    /// <summary>A song's credits in small type at the bottom, on its first and last slides.</summary>
    private static Control Credits(string credits)
    {
        var line = new TextBlock
        {
            Text = credits,
            FontSize = 24,
            FontWeight = FontWeight.Medium,
            Foreground = new SolidColorBrush(Colors.White, 0.9),
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2,
            Width = CanvasWidth - 160,
            Effect = new DropShadowEffect { Color = Color.FromArgb(204, 0, 0, 0), BlurRadius = 6, OffsetX = 0, OffsetY = 1 },
        };
        Canvas.SetLeft(line, 80);
        Canvas.SetBottom(line, 24);
        return line;
    }

    // MARK: Conversions

    public static IBrush Brush(RGBA color) => new SolidColorBrush(Color.FromArgb(
        Channel(color.Alpha), Channel(color.Red), Channel(color.Green), Channel(color.Blue)));

    private static byte Channel(double value) => (byte)Math.Round(Math.Clamp(value, 0, 1) * 255);

    private static Stretch Scaling(string? scaling) => scaling switch
    {
        "fit" => Stretch.Uniform,
        "stretch" => Stretch.Fill,
        _ => Stretch.UniformToFill,
    };

    /// <summary>The slide's font if it's installed, else Segoe UI, so a project from a Mac still shows its words.</summary>
    private static FontFamily Font(string? family) =>
        string.IsNullOrWhiteSpace(family) ? new FontFamily("Segoe UI, Arial") : new FontFamily($"{family}, Segoe UI, Arial");
}

/// <summary>Pictures from the project's media folder, decoded once. Thumbnails use small copies.</summary>
public static class Pictures
{
    private static readonly Dictionary<string, Bitmap?> Full = [];
    private static readonly Dictionary<string, Bitmap?> Small = [];

    public static Bitmap? Load(string? path, bool thumbnail)
    {
        if (string.IsNullOrEmpty(path)) return null;
        var cache = thumbnail ? Small : Full;
        if (cache.TryGetValue(path, out var picture)) return picture;
        try
        {
            using var stream = File.OpenRead(path);
            picture = thumbnail ? Bitmap.DecodeToWidth(stream, 480) : new Bitmap(stream);
        }
        catch (Exception)
        {
            // Missing, or a format this version can't draw (HEIC, say): the slide shows without it.
            picture = null;
        }
        cache[path] = picture;
        return picture;
    }

    /// <summary>Forgets every picture, e.g. after opening another project brought new files.</summary>
    public static void Forget()
    {
        Full.Clear();
        Small.Clear();
    }
}
