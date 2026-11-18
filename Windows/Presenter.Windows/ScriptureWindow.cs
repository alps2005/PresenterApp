using System.Text.Json;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Presenter.Windows.Core;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

/// <summary>
/// Show › Scripture…: type a reference ("Juan 3:16-18") or search for words, check the verses, and add the passage
/// to the show as slides, as the Mac app's Scripture window does. Bibles are public-domain or openly licensed files
/// (Zefania, OSIS, USFX, USX) the operator imports; none come with Presenter. The engine keeps them in
/// %LOCALAPPDATA%\Presenter\Bibles, as the Mac app keeps them beside its project.
/// </summary>
public sealed class ScriptureWindow : Window
{
    private readonly Engine engine;
    /// <summary>The main window's Run: sends a command and redraws the main window.</summary>
    private readonly Func<object, Reply> run;
    private static ScriptureChoices Choices => Settings.Current.Scripture;

    private List<Dictionary<string, string>> bibles = [];
    private bool filling;
    private bool themesFilled;
    private bool found;

    private readonly ComboBox biblePicker = new() { MinWidth = 320 };
    private readonly Button importButton = new() { Content = T("Import Bible…") };
    private readonly Button renameButton = new() { Content = T("Rename…") };
    private readonly Button removeButton = new() { Content = T("Remove…") };
    private readonly TextBox referenceBox = new() { Watermark = T("Reference, like Juan 3:16-18 or 1 Co 13:4-7") };
    private readonly TextBlock lookupNote = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.8 };
    private readonly TextBox searchBox = new() { Watermark = T("Or search for words") };
    private readonly TextBlock searchNote = new() { TextWrapping = TextWrapping.Wrap, Opacity = 0.7, IsVisible = false };
    private readonly ListBox hitsList = new();
    private readonly TextBlock captionText = new() { FontWeight = FontWeight.SemiBold, TextWrapping = TextWrapping.Wrap };
    private readonly StackPanel versesPanel = new() { Spacing = 6 };
    private readonly TextBlock slideCountText = new() { Opacity = 0.7 };
    private readonly ComboBox secondPicker = new() { MinWidth = 200 };
    private readonly ComboBox themePicker = new() { MinWidth = 160 };
    private readonly ComboBox versesPicker = new();
    private readonly CheckBox verseNumbersBox = new() { Content = T("Verse numbers") };
    private readonly CheckBox referenceCheck = new() { Content = T("Reference") };
    private readonly Button addButton = new() { Content = T("Add to Show"), IsDefault = true, MinWidth = 110, Classes = { "accent" } };
    private readonly Control emptyState;
    private readonly Control mainArea;
    private readonly DispatcherTimer lookupPause = new() { Interval = TimeSpan.FromMilliseconds(250) };
    private readonly DispatcherTimer searchPause = new() { Interval = TimeSpan.FromMilliseconds(350) };

    public ScriptureWindow(Engine engine, Func<object, Reply> run)
    {
        this.engine = engine;
        this.run = run;
        Title = T("Scripture");
        Icon = App.Icon;
        Width = 820;
        Height = 640;
        MinWidth = 700;
        MinHeight = 480;
        ShowInTaskbar = false;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        // Screen readers say what each box and list is for; the text around them is only seen.
        SpeakAs(biblePicker, T("Bible"));
        SpeakAs(secondPicker, T("Second Bible"));
        SpeakAs(themePicker, T("Theme"));
        SpeakAs(versesPicker, T("Verses per slide"));
        SpeakAs(referenceBox, T("Reference"));
        SpeakAs(searchBox, T("Search for words"));
        SpeakAs(hitsList, T("Verses found"));

        emptyState = new TextBlock
        {
            Text = T("Import a Bible to start. Presenter reads Zefania, OSIS, USFX and USX files, the free formats public-domain and open translations are shared in, such as the King James Version, the World English Bible or the Reina-Valera 1909. For USX, choose all its book files at once. The README says where to find them."),
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 24),
            Opacity = 0.8,
        };
        mainArea = MainArea();

        var root = new DockPanel { Margin = new Thickness(20) };
        var top = BibleRow();
        DockPanel.SetDock(top, Dock.Top);
        root.Children.Add(top);
        var bottom = BottomArea();
        DockPanel.SetDock(bottom, Dock.Bottom);
        root.Children.Add(bottom);
        var middle = new Panel();
        middle.Children.Add(emptyState);
        middle.Children.Add(mainArea);
        root.Children.Add(middle);
        Content = root;

        for (var count = 1; count <= 4; count++) versesPicker.Items.Add(new ComboBoxItem { Content = count.ToString(), Tag = count });
        versesPicker.SelectedIndex = Math.Clamp(Choices.VersesPerSlide, 1, 4) - 1;
        verseNumbersBox.IsChecked = Choices.ShowsVerseNumbers;
        referenceCheck.IsChecked = Choices.ShowsReference;

        biblePicker.SelectionChanged += (_, _) =>
        {
            if (filling) return;
            Choices.BibleID = SelectedID(biblePicker);
            Settings.Current.SaveQuietly();
            UpdateBibleButtons();
            LookUp();
            Search();
        };
        secondPicker.SelectionChanged += (_, _) =>
        {
            if (filling) return;
            Choices.SecondBibleID = SelectedID(secondPicker);
            Settings.Current.SaveQuietly();
            LookUp();
        };
        versesPicker.SelectionChanged += (_, _) => OptionChanged();
        verseNumbersBox.IsCheckedChanged += (_, _) => OptionChanged();
        referenceCheck.IsCheckedChanged += (_, _) => OptionChanged();
        referenceBox.TextChanged += (_, _) => Restart(lookupPause);
        searchBox.TextChanged += (_, _) => Restart(searchPause);
        lookupPause.Tick += (_, _) =>
        {
            lookupPause.Stop();
            LookUp();
        };
        searchPause.Tick += (_, _) =>
        {
            searchPause.Stop();
            Search();
        };
        hitsList.SelectionChanged += (_, _) =>
        {
            // Choosing a verse found puts its reference in the box, which shows it.
            if (hitsList.SelectedItem is ListBoxItem { Tag: string reference })
            {
                referenceBox.Text = reference;
                lookupPause.Stop();
                LookUp();
            }
        };
        importButton.Click += (_, _) => ImportBible();
        renameButton.Click += (_, _) => RenameBible();
        removeButton.Click += (_, _) => RemoveBible();
        addButton.Click += (_, _) => Add();

        FillBibles(Choices.BibleID);
        Opened += (_, _) => (bibles.Count == 0 ? (Control)importButton : referenceBox).Focus();
        Closed += (_, _) =>
        {
            lookupPause.Stop();
            searchPause.Stop();
        };
    }

    // MARK: - Layout

    private Control BibleRow()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(new TextBlock { Text = T("Bible"), VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(biblePicker);
        row.Children.Add(importButton);
        row.Children.Add(renameButton);
        row.Children.Add(removeButton);
        return row;
    }

    private Control MainArea()
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,16,300"), Margin = new Thickness(0, 16, 0, 0) };

        var left = new DockPanel();
        var findStack = new StackPanel { Spacing = 8 };
        findStack.Children.Add(referenceBox);
        findStack.Children.Add(lookupNote);
        findStack.Children.Add(new Border { Height = 8 });
        findStack.Children.Add(searchBox);
        findStack.Children.Add(searchNote);
        DockPanel.SetDock(findStack, Dock.Top);
        left.Children.Add(findStack);
        hitsList.Margin = new Thickness(0, 8, 0, 0);
        left.Children.Add(hitsList);
        Grid.SetColumn(left, 0);
        grid.Children.Add(left);

        var preview = new StackPanel { Spacing = 10, Margin = new Thickness(12) };
        preview.Children.Add(captionText);
        preview.Children.Add(versesPanel);
        preview.Children.Add(slideCountText);
        var previewBox = new Border
        {
            CornerRadius = new CornerRadius(6),
            Child = new ScrollViewer { Content = preview, HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled },
        };
        App.UseBrush(previewBox, Border.BackgroundProperty, App.PanelBrushKey);
        Grid.SetColumn(previewBox, 2);
        grid.Children.Add(previewBox);
        return grid;
    }

    private Control BottomArea()
    {
        var area = new StackPanel { Spacing = 12, Margin = new Thickness(0, 16, 0, 0) };
        var options = new WrapPanel { Orientation = Orientation.Horizontal };
        options.Children.Add(Labelled(T("Second Bible"), secondPicker));
        options.Children.Add(Labelled(T("Theme"), themePicker));
        options.Children.Add(Labelled(T("Verses per slide"), versesPicker));
        verseNumbersBox.Margin = new Thickness(0, 0, 16, 6);
        referenceCheck.Margin = new Thickness(0, 0, 16, 6);
        options.Children.Add(verseNumbersBox);
        options.Children.Add(referenceCheck);
        area.Children.Add(options);

        var footer = new DockPanel();
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var cancel = new Button { Content = T("Cancel"), IsCancel = true, MinWidth = 90 };
        cancel.Click += (_, _) => Close();
        buttons.Children.Add(cancel);
        buttons.Children.Add(addButton);
        DockPanel.SetDock(buttons, Dock.Right);
        footer.Children.Add(buttons);
        footer.Children.Add(new TextBlock
        {
            Text = T("Public-domain translations only. Presenter doesn't download or include any."),
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Center,
            Opacity = 0.7,
            Classes = { "small" },
        });
        area.Children.Add(footer);
        return area;
    }

    private static Control Labelled(string label, Control control)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Margin = new Thickness(0, 0, 16, 6) };
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(control);
        return row;
    }

    private static void SpeakAs(Control control, string name) => Avalonia.Automation.AutomationProperties.SetName(control, name);

    private static void Restart(DispatcherTimer timer)
    {
        timer.Stop();
        timer.Start();
    }

    // MARK: - Bibles

    /// <summary>The Bibles and themes again, choosing <paramref name="select"/> when it's there.</summary>
    private void FillBibles(Guid? select)
    {
        var reply = engine.Send(new { type = "bibles" });
        bibles = List(reply, "bibles");
        filling = true;
        biblePicker.Items.Clear();
        foreach (var bible in bibles)
            biblePicker.Items.Add(new ComboBoxItem { Content = $"{bible["name"]} ({bible["abbreviation"]})", Tag = Guid.Parse(bible["id"]) });
        Choose(biblePicker, select);
        if (biblePicker.SelectedIndex < 0 && biblePicker.Items.Count > 0) biblePicker.SelectedIndex = 0;
        Choices.BibleID = SelectedID(biblePicker);

        secondPicker.Items.Clear();
        secondPicker.Items.Add(new ComboBoxItem { Content = T("None"), Tag = null });
        foreach (var bible in bibles)
            secondPicker.Items.Add(new ComboBoxItem { Content = $"{bible["name"]} ({bible["abbreviation"]})", Tag = Guid.Parse(bible["id"]) });
        Choose(secondPicker, Choices.SecondBibleID);
        if (secondPicker.SelectedIndex < 0) secondPicker.SelectedIndex = 0;
        Choices.SecondBibleID = SelectedID(secondPicker);

        // The theme starts on the one the Mac app would suggest (named Scripture, else the default), each time.
        if (!themesFilled)
        {
            themePicker.Items.Add(new ComboBoxItem { Content = T("None"), Tag = null });
            foreach (var theme in List(reply, "themes"))
                themePicker.Items.Add(new ComboBoxItem { Content = theme["name"], Tag = Guid.Parse(theme["id"]) });
            Choose(themePicker, Guid.TryParse(reply.GetString("suggestedThemeID"), out var suggested) ? suggested : null);
            if (themePicker.SelectedIndex < 0) themePicker.SelectedIndex = 0;
            themesFilled = true;
        }
        filling = false;

        emptyState.IsVisible = bibles.Count == 0;
        mainArea.IsVisible = bibles.Count > 0;
        biblePicker.IsVisible = bibles.Count > 0;
        secondPicker.IsEnabled = bibles.Count > 1;
        Settings.Current.SaveQuietly();
        UpdateBibleButtons();
        LookUp();
        Search();
    }

    private void UpdateBibleButtons()
    {
        var chosen = SelectedID(biblePicker) is not null;
        renameButton.IsVisible = chosen;
        removeButton.IsVisible = chosen;
    }

    private async void ImportBible()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = T("Import Bible"),
            AllowMultiple = true,
            FileTypeFilter =
            [
                new FilePickerFileType(T("Bible files (Zefania, OSIS, USFX, USX)")) { Patterns = ["*.xml", "*.osis", "*.usfx", "*.usx"] },
                FilePickerFileTypes.All,
            ],
        });
        var paths = files.Select(f => f.TryGetLocalPath()).OfType<string>().ToArray();
        if (paths.Length == 0) return;
        importButton.IsEnabled = false;
        lookupNote.Text = T("Reading the Bible…");
        // Let "Reading the Bible…" show before the engine reads a whole Bible on this thread.
        await Task.Delay(50);
        var reply = engine.Send(new { type = "importBible", paths });
        importButton.IsEnabled = true;
        lookupNote.Text = "";
        if (!reply.Ok)
        {
            await Dialogs.Inform(this, T("The Bible wasn't imported"), reply.Error ?? "");
            return;
        }
        FillBibles(Guid.TryParse(reply.GetString("bibleID"), out var id) ? id : null);
        referenceBox.Focus();
    }

    private async void RenameBible()
    {
        if (SelectedID(biblePicker) is not { } id) return;
        var bible = bibles.First(b => Guid.Parse(b["id"]) == id);
        var name = await Dialogs.Prompt(this, T("Rename Bible"), T("Name"), bible["name"], T("Next"));
        if (string.IsNullOrWhiteSpace(name)) return;
        var abbreviation = await Dialogs.Prompt(this, T("Rename Bible"), T("Abbreviation, shown on slides"), bible["abbreviation"], T("Rename"));
        if (abbreviation is null) return;
        var reply = engine.Send(new { type = "renameBible", bibleID = id, title = name, abbreviation });
        if (!reply.Ok)
        {
            await Dialogs.Inform(this, T("The Bible wasn't renamed"), reply.Error ?? "");
            return;
        }
        FillBibles(id);
    }

    private async void RemoveBible()
    {
        if (SelectedID(biblePicker) is not { } id) return;
        var sure = await Dialogs.Confirm(this, T("Remove this Bible?"),
            T("Slides already made from it stay as they are. You can import the file again later."), T("Remove"));
        if (!sure) return;
        var reply = engine.Send(new { type = "removeBible", bibleID = id });
        if (!reply.Ok) await Dialogs.Inform(this, T("The Bible wasn't removed"), reply.Error ?? "");
        FillBibles(null);
    }

    // MARK: - Passages

    private void OptionChanged()
    {
        if (filling) return;
        Choices.VersesPerSlide = versesPicker.SelectedItem is ComboBoxItem { Tag: int count } ? count : 2;
        Choices.ShowsVerseNumbers = verseNumbersBox.IsChecked == true;
        Choices.ShowsReference = referenceCheck.IsChecked == true;
        Settings.Current.SaveQuietly();
        LookUp();
    }

    /// <summary>The fields every passage command takes.</summary>
    private object PassageCommand(string type, Guid bibleID) => new
    {
        type,
        bibleID,
        text = referenceBox.Text ?? "",
        secondBibleID = SelectedID(secondPicker),
        versesPerSlide = Choices.VersesPerSlide,
        showsVerseNumbers = Choices.ShowsVerseNumbers,
        showsReference = Choices.ShowsReference,
        themeID = SelectedID(themePicker),
    };

    /// <summary>Shows the verses for the typed reference, or why there are none.</summary>
    private void LookUp()
    {
        versesPanel.Children.Clear();
        captionText.Text = "";
        slideCountText.Text = "";
        found = false;
        addButton.IsEnabled = false;
        if (SelectedID(biblePicker) is not { } id || string.IsNullOrWhiteSpace(referenceBox.Text))
        {
            lookupNote.Text = "";
            return;
        }
        var reply = engine.Send(PassageCommand("lookUpScripture", id));
        if (!reply.Ok)
        {
            lookupNote.Text = reply.Error;
            return;
        }
        found = true;
        addButton.IsEnabled = true;
        lookupNote.Text = reply.GetString("secondMissing") ?? "";
        captionText.Text = reply.GetString("caption");
        var verses = List(reply, "verses");
        var chapters = verses.Select(v => v["chapter"]).Distinct().Count();
        foreach (var verse in verses)
        {
            var number = chapters > 1 ? $"{verse["chapter"]}:{verse["number"]}" : verse["number"];
            var row = new DockPanel();
            var label = new TextBlock { Text = number, Opacity = 0.6, MinWidth = 34, Classes = { "small" } };
            DockPanel.SetDock(label, Dock.Left);
            row.Children.Add(label);
            row.Children.Add(new TextBlock { Text = verse["text"], TextWrapping = TextWrapping.Wrap });
            versesPanel.Children.Add(row);
        }
        var slides = reply.GetInt("slideCount");
        slideCountText.Text = slides == 1 ? T("1 slide") : T("{0} slides", slides);
    }

    /// <summary>Verses with all the words typed. Choosing one shows it.</summary>
    private void Search()
    {
        hitsList.Items.Clear();
        searchNote.IsVisible = false;
        if (SelectedID(biblePicker) is not { } id || string.IsNullOrWhiteSpace(searchBox.Text)) return;
        var reply = engine.Send(new { type = "searchBible", bibleID = id, text = searchBox.Text });
        if (!reply.Ok)
        {
            searchNote.Text = reply.Error;
            searchNote.IsVisible = true;
            return;
        }
        var hits = List(reply, "hits");
        foreach (var hit in hits)
        {
            var row = new StackPanel { Spacing = 2 };
            row.Children.Add(new TextBlock { Text = hit["reference"], FontWeight = FontWeight.SemiBold });
            row.Children.Add(new TextBlock { Text = hit["text"], TextWrapping = TextWrapping.Wrap, MaxLines = 2, TextTrimming = TextTrimming.CharacterEllipsis, Opacity = 0.8 });
            var item = new ListBoxItem { Content = row, Tag = hit["reference"] };
            SpeakAs(item, hit["reference"] + ": " + hit["text"]);
            hitsList.Items.Add(item);
        }
        searchNote.Text = hits.Count switch
        {
            0 => T("No verses have all those words."),
            >= 200 => T("The first 200 verses. Add a word to narrow it down."),
            _ => "",
        };
        searchNote.IsVisible = searchNote.Text.Length > 0;
    }

    private void Add()
    {
        if (!found || SelectedID(biblePicker) is not { } id) return;
        var reply = run(PassageCommand("addScripture", id));
        if (reply.Ok) Close();
        else lookupNote.Text = reply.Error;
    }

    // MARK: - Helpers

    private static Guid? SelectedID(ComboBox box) => box.SelectedItem is ComboBoxItem { Tag: Guid id } ? id : null;

    private static void Choose(ComboBox box, Guid? id)
    {
        if (id is null) return;
        box.SelectedItem = box.Items.OfType<ComboBoxItem>().FirstOrDefault(i => i.Tag is Guid tag && tag == id);
    }

    /// <summary>A list of objects in the reply, each as names and text.</summary>
    private static List<Dictionary<string, string>> List(Reply reply, string name)
    {
        if (!reply.Values.TryGetProperty(name, out var list) || list.ValueKind != JsonValueKind.Array) return [];
        return list.EnumerateArray()
            .Select(entry => entry.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() ?? "" : p.Value.ToString()))
            .ToList();
    }
}
