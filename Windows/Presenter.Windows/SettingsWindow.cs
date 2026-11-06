using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

/// <summary>
/// File › Settings…: appearance, text size, language, and the colours for LIVE and each kind of song section, like
/// the Mac app's Settings. Everything but the language shows straight away; the language applies on the next start,
/// which Restart Presenter Now does when nothing is on the audience output.
/// </summary>
public sealed class SettingsWindow : Window
{
    private readonly Func<bool> isPresenting;
    private readonly LanguageChoice launchedWith = Settings.Current.Language;
    private readonly StackPanel restartRow = new() { Spacing = 8, IsVisible = false };
    private readonly TextBlock restartNote = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.7, Classes = { "small" } };
    private readonly Button restartButton = new() { Content = T("Restart Presenter Now") };
    private readonly Button resetButton = new() { Content = T("Restore Defaults") };
    private readonly StackPanel colourRows = new() { Spacing = 6 };
    /// <summary>A colour picker reports every step of a drag; the colour is kept once the dragging pauses.</summary>
    private readonly DispatcherTimer colourPause = new() { Interval = TimeSpan.FromMilliseconds(300) };
    private Action? pendingColour;
    /// <summary>True while a colour chosen here is kept, so the pickers aren't rebuilt under the operator's mouse.</summary>
    private bool keepingColour;

    public SettingsWindow(Func<bool> isPresenting)
    {
        this.isPresenting = isPresenting;
        Title = T("Settings");
        Width = 520;
        Height = 720;
        MinWidth = 440;
        MinHeight = 400;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        colourPause.Tick += (_, _) =>
        {
            colourPause.Stop();
            KeepPendingColour();
        };

        var page = new StackPanel { Spacing = 10, Margin = new Thickness(24, 20) };

        page.Children.Add(Heading(T("APPEARANCE")));
        page.Children.Add(Choice(
            [(AppearanceChoice.Dark, T("Dark")), (AppearanceChoice.Light, T("Light")), (AppearanceChoice.System, T("Same as Windows"))],
            Settings.Current.Appearance, chosen => { Settings.Current.Appearance = chosen; Settings.Current.Save(); }));
        page.Children.Add(Note(T("Presenter is dark unless you choose otherwise, so it stays quiet in a dark room.")));

        page.Children.Add(Heading(T("TEXT SIZE")));
        page.Children.Add(Choice(
            [(TextSizeChoice.Small, T("Small")), (TextSizeChoice.Standard, T("Standard")), (TextSizeChoice.Large, T("Large")),
             (TextSizeChoice.ExtraLarge, T("Extra Large"))],
            Settings.Current.TextSize, chosen => { Settings.Current.TextSize = chosen; Settings.Current.Save(); }));
        page.Children.Add(Note(T("The text in Presenter's windows. Slides and the audience output keep their own sizes.")));

        page.Children.Add(Heading(T("LANGUAGE")));
        // Each language by its own name, so it can be found whatever language the screen is in.
        page.Children.Add(Choice(
            [(LanguageChoice.System, T("Same as Windows")), (LanguageChoice.English, "English"), (LanguageChoice.Spanish, "Español")],
            Settings.Current.Language, chosen =>
            {
                Settings.Current.Language = chosen;
                Settings.Current.Save();
                UpdateRestart();
            }));
        page.Children.Add(Note(T("Menus, windows and messages. Your songs and slides stay as you wrote them.")));
        restartButton.HorizontalAlignment = HorizontalAlignment.Left;
        restartButton.Click += (_, _) => Restart();
        restartRow.Children.Add(new TextBlock { Text = T("Presenter changes language the next time it opens."), TextWrapping = TextWrapping.Wrap });
        restartRow.Children.Add(restartNote);
        restartRow.Children.Add(restartButton);
        page.Children.Add(restartRow);

        page.Children.Add(Heading(T("COLOURS")));
        page.Children.Add(colourRows);
        page.Children.Add(Note(T("LIVE marks what's on the audience output now. Song sections colour the labels on slide thumbnails, such as Verse 1 or Coro.")));

        resetButton.Click += (_, _) => Settings.Current.ResetLook();
        var footer = new DockPanel { Margin = new Thickness(0, 12, 0, 0) };
        DockPanel.SetDock(resetButton, Dock.Right);
        footer.Children.Add(resetButton);
        footer.Children.Add(new TextBlock
        {
            Text = T("Kept on this PC, not in the project."),
            Opacity = 0.7,
            VerticalAlignment = VerticalAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Classes = { "small" },
        });
        page.Children.Add(footer);

        Content = new ScrollViewer { Content = page };

        FillColours();
        UpdateRestart();
        Settings.Changed += OnSettingsChanged;
        if (Application.Current is { } app) app.ActualThemeVariantChanged += OnThemeChanged;
        Closed += (_, _) =>
        {
            Settings.Changed -= OnSettingsChanged;
            if (Application.Current is { } app) app.ActualThemeVariantChanged -= OnThemeChanged;
            colourPause.Stop();
            KeepPendingColour();
        };
    }

    private void KeepPendingColour()
    {
        var keep = pendingColour;
        pendingColour = null;
        keepingColour = true;
        try { keep?.Invoke(); }
        finally { keepingColour = false; }
    }

    private void OnSettingsChanged()
    {
        resetButton.IsEnabled = Settings.Current.IsLookCustomized;
        // A colour chosen here already shows in its picker; rebuilding the pickers would close it mid-choice.
        if (!keepingColour && pendingColour is null) FillColours();
    }

    private void OnThemeChanged(object? sender, EventArgs e) => FillColours();

    /// <summary>The pickers, again: after Restore Defaults, or when the theme's default colours change.</summary>
    private void FillColours()
    {
        resetButton.IsEnabled = Settings.Current.IsLookCustomized;
        colourRows.Children.Clear();
        colourRows.Children.Add(ColourRow(LiveTag(), Settings.Current.Live, colour => Settings.Current.SetLiveColor(colour)));
        foreach (var (key, name) in Settings.SectionKinds)
        {
            colourRows.Children.Add(ColourRow(MainWindow.SectionTag(T(name), key), Settings.Current.SectionColor(key, App.IsDark),
                colour => Settings.Current.SetSectionColor(key, colour)));
        }
    }

    private Control ColourRow(Control label, Color colour, Action<Color> keep)
    {
        var picker = new ColorPicker
        {
            Color = colour,
            IsAlphaEnabled = false,
            IsAlphaVisible = false,
            HorizontalAlignment = HorizontalAlignment.Right,
        };
        picker.ColorChanged += (_, e) =>
        {
            var chosen = Color.FromRgb(e.NewColor.R, e.NewColor.G, e.NewColor.B);
            pendingColour = () => keep(chosen);
            colourPause.Stop();
            colourPause.Start();
        };
        var row = new DockPanel();
        DockPanel.SetDock(picker, Dock.Right);
        row.Children.Add(picker);
        label.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(label);
        return row;
    }

    private static Control LiveTag() => new Border
    {
        Background = new SolidColorBrush(Settings.Current.Live),
        CornerRadius = new CornerRadius(9),
        Padding = new Thickness(7, 1),
        HorizontalAlignment = HorizontalAlignment.Left,
        Child = new TextBlock { Text = T("LIVE"), FontWeight = FontWeight.SemiBold, Foreground = Brushes.White, Classes = { "small" } },
    };

    private void UpdateRestart()
    {
        restartRow.IsVisible = Settings.Current.Language != launchedWith;
        var presenting = isPresenting();
        restartButton.IsEnabled = !presenting;
        restartNote.Text = presenting ? T("Something is on the audience output. Restart after the service.") : "";
        restartNote.IsVisible = presenting;
    }

    private void Restart()
    {
        if (isPresenting())
        {
            UpdateRestart();
            return;
        }
        App.RestartWhenClosed = true;
        // Closing the operator window saves the project and ends the app; Program starts it again.
        (Owner as Window)?.Close();
    }

    private static ComboBox Choice<TChoice>((TChoice Value, string Title)[] choices, TChoice current, Action<TChoice> choose)
        where TChoice : struct, Enum
    {
        var box = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var (value, title) in choices) box.Items.Add(new ComboBoxItem { Content = title, Tag = value });
        box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => i.Tag is TChoice value && value.Equals(current));
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedItem is ComboBoxItem { Tag: TChoice value }) choose(value);
        };
        return box;
    }

    private static TextBlock Heading(string text)
    {
        var heading = new TextBlock { Text = text, FontWeight = FontWeight.SemiBold, Margin = new Thickness(0, 10, 0, 0), Classes = { "heading" } };
        App.UseBrush(heading, TextBlock.ForegroundProperty, App.HeaderBrushKey);
        return heading;
    }

    private static TextBlock Note(string text) => new()
    {
        Text = text,
        TextWrapping = TextWrapping.Wrap,
        Opacity = 0.7,
        Classes = { "small" },
    };
}
