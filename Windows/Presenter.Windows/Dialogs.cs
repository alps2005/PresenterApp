using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

/// <summary>The app's small windows: typing a song's words, a name, and yes-or-no questions.</summary>
public static class Dialogs
{
    public static string WordsHint => T(
        "A blank line starts a new slide. A line that's only a section name (Verse 1, Chorus, Coro, Puente…) " +
        "names the slides after it and isn't shown.");

    /// <summary>A title and the words, New Song style. Null when cancelled.</summary>
    public static Task<(string Title, string Text)?> Words(Window owner, string heading, string title, string text, string confirm)
    {
        var dialog = Dialog(heading, 640, 620);
        var titleBox = new TextBox { Text = title, Watermark = T("Title") };
        var wordsBox = new TextBox
        {
            Text = text,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            Watermark = T("Verse 1\nThe first line\nThe second line\n\nChorus\n…"),
            FontFamily = new FontFamily("Cascadia Mono, Consolas, monospace"),
        };
        ScrollViewer.SetVerticalScrollBarVisibility(wordsBox, Avalonia.Controls.Primitives.ScrollBarVisibility.Auto);

        var body = new DockPanel { Margin = new Thickness(20) };
        var top = new StackPanel { Spacing = 8, Margin = new Thickness(0, 0, 0, 12) };
        top.Children.Add(new TextBlock { Text = T("Title") });
        top.Children.Add(titleBox);
        top.Children.Add(new TextBlock { Text = T("Words"), Margin = new Thickness(0, 8, 0, 0) });
        DockPanel.SetDock(top, Dock.Top);
        body.Children.Add(top);

        var bottom = new StackPanel { Spacing = 12, Margin = new Thickness(0, 12, 0, 0) };
        bottom.Children.Add(new TextBlock { Text = WordsHint, TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        bottom.Children.Add(Buttons(dialog, confirm, () => ((string Title, string Text)?)(titleBox.Text ?? "", wordsBox.Text ?? "")));
        DockPanel.SetDock(bottom, Dock.Bottom);
        body.Children.Add(bottom);
        body.Children.Add(wordsBox);

        dialog.Content = body;
        dialog.Opened += (_, _) => (string.IsNullOrEmpty(title) ? titleBox : wordsBox).Focus();
        return dialog.ShowDialog<(string Title, string Text)?>(owner);
    }

    /// <summary>A line of text, e.g. a new name. Null when cancelled.</summary>
    public static Task<string?> Prompt(Window owner, string heading, string label, string text, string confirm)
    {
        var dialog = Dialog(heading, 420, 0);
        var box = new TextBox { Text = text };
        var body = new StackPanel { Spacing = 12, Margin = new Thickness(20) };
        body.Children.Add(new TextBlock { Text = label });
        body.Children.Add(box);
        body.Children.Add(Buttons(dialog, confirm, () => box.Text ?? ""));
        dialog.Content = body;
        dialog.Opened += (_, _) =>
        {
            box.Focus();
            box.SelectAll();
        };
        return dialog.ShowDialog<string?>(owner);
    }

    /// <summary>Asks before something that can't easily be taken back. True to go ahead.</summary>
    public static async Task<bool> Confirm(Window owner, string heading, string message, string confirm)
    {
        var dialog = Dialog(heading, 460, 0);
        var body = new StackPanel { Spacing = 16, Margin = new Thickness(20) };
        body.Children.Add(new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(Buttons(dialog, confirm, () => (bool?)true));
        dialog.Content = body;
        return await dialog.ShowDialog<bool?>(owner) == true;
    }

    /// <summary>Tells the operator something, with an OK button.</summary>
    public static Task Inform(Window owner, string heading, string message)
    {
        var dialog = Dialog(heading, 480, 0);
        var body = new StackPanel { Spacing = 16, Margin = new Thickness(20) };
        body.Children.Add(new SelectableTextBlock { Text = message, TextWrapping = TextWrapping.Wrap });
        var ok = new Button { Content = T("OK"), IsDefault = true, IsCancel = true, HorizontalAlignment = HorizontalAlignment.Right, MinWidth = 90 };
        ok.Click += (_, _) => dialog.Close();
        body.Children.Add(ok);
        dialog.Content = body;
        return dialog.ShowDialog(owner);
    }

    private static Window Dialog(string heading, double width, double height)
    {
        var dialog = new Window
        {
            Title = heading,
            Icon = App.Icon,
            Width = width,
            CanResize = height > 0,
            ShowInTaskbar = false,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
        };
        if (height > 0) dialog.Height = height;
        else dialog.SizeToContent = SizeToContent.Height;
        return dialog;
    }

    private static Control Buttons<TResult>(Window dialog, string confirm, Func<TResult> result)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = T("Cancel"), IsCancel = true, MinWidth = 90 };
        cancel.Click += (_, _) => dialog.Close(default(TResult));
        var ok = new Button { Content = confirm, IsDefault = true, MinWidth = 90, Classes = { "accent" } };
        ok.Click += (_, _) => dialog.Close(result());
        row.Children.Add(cancel);
        row.Children.Add(ok);
        return row;
    }
}
