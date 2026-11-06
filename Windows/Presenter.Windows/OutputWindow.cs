using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using Avalonia.Platform;
using Presenter.Windows.Core;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

/// <summary>
/// What the audience sees: full screen on a second display, or, on a computer with one screen, in an ordinary window
/// to try things out. Keys pressed here go to the operator window.
/// </summary>
public sealed class OutputWindow : Window
{
    public OutputWindow(Screen? screen, Action<KeyEventArgs> keys)
    {
        Background = Brushes.Black;
        Content = new SlideView(null);
        KeyDown += (_, e) => keys(e);
        if (screen is null)
        {
            Title = T("Presenter — Audience (test window)");
            Width = 960;
            Height = 540;
            return;
        }
        Title = T("Presenter — Audience");
        ShowInTaskbar = false;
        SystemDecorations = SystemDecorations.None;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Position = screen.Bounds.Position;
        Width = screen.Bounds.Width / screen.Scaling;
        Height = screen.Bounds.Height / screen.Scaling;
        Topmost = true;
        Cursor = new Cursor(StandardCursorType.None);
        Opened += (_, _) => WindowState = WindowState.FullScreen;
    }

    public void Display(SlideModel? audience, string? credits)
    {
        Content = new SlideView(audience, credits, checkerboard: false);
    }
}
