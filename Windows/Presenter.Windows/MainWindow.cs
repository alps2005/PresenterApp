using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Interactivity;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Platform;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using Presenter.Windows.Core;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

/// <summary>
/// The operator window: the show's items and the library on the left, the selected item's slides in the middle,
/// and the audience preview with the live controls on the right. Every change goes to the engine as a command;
/// the window then reads the engine's state and redraws what changed.
/// </summary>
public sealed class MainWindow : Window
{
    private const double TileWidth = 224;
    private const double TileHeight = TileWidth * 9 / 16;

    /// <summary>LIVE's colour, from Settings.</summary>
    private static IBrush LiveBrush => new SolidColorBrush(Settings.Current.Live);

    private readonly Engine engine;
    private EngineState state;
    private OutputWindow? output;

    private int shownRevision = -1;
    private Guid? shownShow;
    private Guid? shownItem;
    private string? shownAudience;
    /// <summary>True while the window sets its own lists, so their change events don't send commands back.</summary>
    private bool updating;

    private readonly ComboBox showPicker = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly ListBox itemList = new();
    private readonly ListBox libraryList = new();
    private readonly TextBlock itemHeading = new() { FontWeight = FontWeight.SemiBold, VerticalAlignment = VerticalAlignment.Center, Classes = { "title" } };
    private readonly Button editWordsButton = new() { Content = T("Edit Words…") };
    private readonly WrapPanel slideGrid = new() { Margin = new Thickness(12) };
    private readonly TextBlock emptyHint = new()
    {
        Text = T("Add a song with Show › New Song… (Ctrl+N), or import song files with Show › Import Songs… (Ctrl+I)."),
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(24),
        Opacity = 0.7,
    };
    private readonly Dictionary<SlidePosition, Border> tiles = [];
    private readonly Border audiencePreview = new() { Height = 396 * 9 / 16, Background = Brushes.Black };
    private readonly ComboBox displayPicker = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly Button outputButton = new() { HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Center };
    private readonly Button blackoutButton = LiveButton(T("Blackout"), "F4");
    private readonly Button restoreButton = LiveButton(T("Restore"), "F5");
    private readonly Border problemBar = new() { Padding = new Thickness(12, 8), IsVisible = false };
    private readonly TextBlock problemText = new() { TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock status = new() { Margin = new Thickness(12, 4), Opacity = 0.8, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly MenuItem undoItem = new() { Header = T("_Undo"), InputGesture = new KeyGesture(Key.Z, KeyModifiers.Control) };
    private readonly MenuItem redoItem = new() { Header = T("_Redo"), InputGesture = new KeyGesture(Key.Y, KeyModifiers.Control) };
    private SettingsWindow? settingsWindow;

    public MainWindow(Engine engine)
    {
        this.engine = engine;
        state = engine.State();
        Title = "Presenter";
        Icon = App.Icon;
        Width = 1400;
        Height = 860;
        MinWidth = 1000;
        MinHeight = 600;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new DockPanel();
        var menu = BuildMenu();
        DockPanel.SetDock(menu, Dock.Top);
        root.Children.Add(menu);
        problemBar.Child = ProblemContent();
        App.UseBrush(problemBar, Border.BackgroundProperty, App.ProblemBrushKey);
        DockPanel.SetDock(problemBar, Dock.Top);
        root.Children.Add(problemBar);
        var statusBar = new Border { Child = status };
        App.UseBrush(statusBar, Border.BackgroundProperty, App.PanelBrushKey);
        DockPanel.SetDock(statusBar, Dock.Bottom);
        root.Children.Add(statusBar);

        var columns = new Grid { ColumnDefinitions = new ColumnDefinitions("280,4,*,4,420") };
        AddColumn(columns, LeftColumn(), 0);
        AddColumn(columns, Splitter(), 1);
        AddColumn(columns, MiddleColumn(), 2);
        AddColumn(columns, Splitter(), 3);
        AddColumn(columns, RightColumn(), 4);
        root.Children.Add(columns);
        Content = root;

        // Live keys work wherever the focus is, except while typing.
        AddHandler(KeyDownEvent, OnKey, RoutingStrategies.Tunnel);
        // A button clicks when Space comes up, so after clicking one, Space would press it again as well as moving
        // on (closing the audience output mid-song, say). Space is the Next key: its key-up stops here.
        AddHandler(KeyUpEvent, (_, e) =>
        {
            if (e.Key == Key.Space && e.KeyModifiers == KeyModifiers.None && !IsTyping()) e.Handled = true;
        }, RoutingStrategies.Tunnel);

        // A change in Settings, or Windows switching between light and dark, redraws the colours.
        Settings.Changed += OnLookChanged;
        if (Application.Current is { } app) app.ActualThemeVariantChanged += OnThemeChanged;

        var ticker = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        ticker.Tick += (_, _) =>
        {
            if (engine.Tick()) Refresh();
        };
        ticker.Start();

        Opened += (_, _) =>
        {
            FillDisplays();
            // With a second display, the audience output opens on it straight away.
            if (Screens.All.Count > 1) ToggleOutput();
            Refresh();
        };
        Closed += (_, _) =>
        {
            Settings.Changed -= OnLookChanged;
            if (Application.Current is { } app) app.ActualThemeVariantChanged -= OnThemeChanged;
            settingsWindow?.Close();
            ticker.Stop();
            output?.Close();
            engine.Dispose();
        };
        Refresh();
    }

    private void OnLookChanged() => Redraw();

    private void OnThemeChanged(object? sender, EventArgs e) => Redraw();

    /// <summary>Draws everything again, for new colours or a new theme.</summary>
    private void Redraw()
    {
        shownRevision = -1;
        shownAudience = null;
        Refresh();
    }

    private static GridSplitter Splitter()
    {
        var splitter = new GridSplitter();
        App.UseBrush(splitter, BackgroundProperty, App.PanelBrushKey);
        return splitter;
    }

    private static void AddColumn(Grid grid, Control control, int column)
    {
        Grid.SetColumn(control, column);
        grid.Children.Add(control);
    }

    // MARK: - Layout

    private Menu BuildMenu()
    {
        undoItem.Click += (_, _) => Run(new { type = "undo" });
        redoItem.Click += (_, _) => Run(new { type = "redo" });
        return new Menu
        {
            Items =
            {
                Submenu(T("_File"),
                    Item(T("_Open Project File…"), OpenProjectFile, new KeyGesture(Key.O, KeyModifiers.Control)),
                    Item(T("_Export Project…"), ExportProject, new KeyGesture(Key.E, KeyModifiers.Control)),
                    new Separator(),
                    Item(T("Open the _Project Folder"), () => App.OpenInShell(engine.DataDirectory)),
                    new Separator(),
                    Item(T("_Settings…"), ShowSettings, new KeyGesture(Key.OemComma, KeyModifiers.Control)),
                    new Separator(),
                    Item(T("E_xit"), Close)),
                Submenu(T("_Edit"), undoItem, redoItem),
                Submenu(T("_Show"),
                    Item(T("_New Song…"), NewSong, new KeyGesture(Key.N, KeyModifiers.Control)),
                    Item(T("_Import Songs…"), ImportSongs, new KeyGesture(Key.I, KeyModifiers.Control)),
                    new Separator(),
                    Item(T("New _Show…"), NewShow),
                    Item(T("_Rename Show…"), RenameShow),
                    Item(T("_Delete Show…"), DeleteShow)),
                Submenu(T("_Live"),
                    Item(T("_Next Slide"), () => Run(new { type = "next" }), new KeyGesture(Key.Right)),
                    Item(T("_Previous Slide"), () => Run(new { type = "previous" }), new KeyGesture(Key.Left)),
                    new Separator(),
                    Item(T("Clear _All"), () => Run(new { type = "clearAll" }), new KeyGesture(Key.F1)),
                    Item(T("Clear _Slide"), () => Run(new { type = "clearSlide" }), new KeyGesture(Key.F2)),
                    Item(T("Clear _Background"), () => Run(new { type = "clearBackground" }), new KeyGesture(Key.F3)),
                    Item(T("Blac_kout"), () => Run(new { type = "blackout" }), new KeyGesture(Key.F4)),
                    Item(T("_Restore Output"), () => Run(new { type = "restore" }), new KeyGesture(Key.F5)),
                    new Separator(),
                    Item(T("Show or Hide the Audience _Output"), ToggleOutput, new KeyGesture(Key.F11))),
                Submenu(T("_Help"),
                    Item(T("_Keyboard Shortcuts"), ShowShortcuts),
                    Item(T("_Report a Problem or Idea…"), () => App.OpenInShell(App.IssuesURL)),
                    Item(T("Open the Problem _Logs Folder"), () =>
                    {
                        Directory.CreateDirectory(CrashLog.Directory);
                        App.OpenInShell(CrashLog.Directory);
                    }),
                    new Separator(),
                    Item(T("_About Presenter"), ShowAbout)),
            },
        };
    }

    private static MenuItem Submenu(string header, params Control[] items)
    {
        var submenu = new MenuItem { Header = header };
        foreach (var item in items) submenu.Items.Add(item);
        return submenu;
    }

    private static MenuItem Item(string header, Action action, KeyGesture? gesture = null)
    {
        var item = new MenuItem { Header = header, InputGesture = gesture };
        item.Click += (_, _) => action();
        return item;
    }

    private Control ProblemContent()
    {
        var dismiss = new Button { Content = T("Dismiss"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
        dismiss.Click += (_, _) => Run(new { type = "dismissProblem" });
        var row = new DockPanel();
        DockPanel.SetDock(dismiss, Dock.Right);
        row.Children.Add(dismiss);
        row.Children.Add(problemText);
        return row;
    }

    private Control LeftColumn()
    {
        var grid = new Grid { RowDefinitions = new RowDefinitions("Auto,Auto,*,Auto,*"), Margin = new Thickness(10) };
        showPicker.SelectionChanged += (_, _) =>
        {
            if (!updating && showPicker.SelectedItem is ComboBoxItem { Tag: Guid id } && id != state.ActiveShowID)
                Run(new { type = "openShow", showID = id });
        };
        AddRow(grid, Heading(T("SHOW")), 0);
        AddRow(grid, showPicker, 1);
        itemList.Margin = new Thickness(0, 8, 0, 0);
        itemList.SelectionChanged += (_, _) =>
        {
            if (!updating && itemList.SelectedItem is ListBoxItem { Tag: ItemInfo item } && item.ID != state.SelectedItemID)
                Run(new { type = "selectItem", itemID = item.ID });
        };
        AddRow(grid, itemList, 2);
        var libraryHeading = Heading(T("LIBRARY  ·  double-click to add to the show"));
        libraryHeading.Margin = new Thickness(0, 16, 0, 0);
        AddRow(grid, libraryHeading, 3);
        libraryList.Margin = new Thickness(0, 8, 0, 0);
        AddRow(grid, libraryList, 4);
        return grid;
    }

    private Control MiddleColumn()
    {
        editWordsButton.Click += (_, _) =>
        {
            if (SelectedItem() is { } item) EditWords(item.PresentationID);
        };
        var header = new DockPanel { Margin = new Thickness(12, 10, 12, 0) };
        DockPanel.SetDock(editWordsButton, Dock.Right);
        header.Children.Add(editWordsButton);
        header.Children.Add(itemHeading);

        var column = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        column.Children.Add(header);
        var content = new StackPanel();
        content.Children.Add(emptyHint);
        content.Children.Add(slideGrid);
        column.Children.Add(new ScrollViewer { Content = content, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        return column;
    }

    private Control RightColumn()
    {
        var panel = new StackPanel { Spacing = 10, Margin = new Thickness(12) };
        panel.Children.Add(Heading(T("AUDIENCE")));
        panel.Children.Add(audiencePreview);

        panel.Children.Add(Heading(T("OUTPUT")));
        displayPicker.DropDownOpened += (_, _) => FillDisplays();
        panel.Children.Add(displayPicker);
        outputButton.Click += (_, _) => ToggleOutput();
        panel.Children.Add(outputButton);

        panel.Children.Add(Heading(T("LIVE")));
        var steps = new Grid { ColumnDefinitions = new ColumnDefinitions("*,8,*") };
        var previous = LiveButton(T("◀ Previous"), "←");
        previous.Click += (_, _) => Run(new { type = "previous" });
        var next = LiveButton(T("Next ▶"), T("→ or Space"));
        next.Click += (_, _) => Run(new { type = "next" });
        AddColumn(steps, previous, 0);
        AddColumn(steps, next, 2);
        panel.Children.Add(steps);

        var clears = new UniformGrid { Columns = 2 };
        foreach (var (label, key, type) in new[]
                 {
                     (T("Clear All"), "F1", "clearAll"), (T("Clear Slide"), "F2", "clearSlide"),
                     (T("Clear Background"), "F3", "clearBackground"),
                 })
        {
            var button = LiveButton(label, key);
            button.Margin = new Thickness(0, 0, 6, 6);
            button.Click += (_, _) => Run(new { type });
            clears.Children.Add(button);
        }
        blackoutButton.Margin = new Thickness(0, 0, 6, 6);
        blackoutButton.Click += (_, _) => Run(new { type = "blackout" });
        clears.Children.Add(blackoutButton);
        restoreButton.Margin = new Thickness(0, 0, 6, 6);
        restoreButton.Click += (_, _) => Run(new { type = "restore" });
        clears.Children.Add(restoreButton);
        panel.Children.Add(clears);

        panel.Children.Add(new TextBlock
        {
            Text = T("Click a slide to show it. Section keys jump within the song: V verse, C chorus, P pre-chorus, " +
                     "B bridge, T tag, I intro, E ending, N interlude (press again for the next one)."),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.6,
            Classes = { "small" },
        });
        return new ScrollViewer { Content = panel };
    }

    private static Button LiveButton(string label, string key)
    {
        var content = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        content.Children.Add(new TextBlock { Text = label, HorizontalAlignment = HorizontalAlignment.Center });
        content.Children.Add(new TextBlock { Text = key, Opacity = 0.55, HorizontalAlignment = HorizontalAlignment.Center, Classes = { "tiny" } });
        var button = new Button
        {
            Content = content,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            Padding = new Thickness(8, 6),
            Focusable = false,
        };
        // Screen readers say the label, not the panel it's drawn in.
        Avalonia.Automation.AutomationProperties.SetName(button, label);
        return button;
    }

    private static TextBlock Heading(string text)
    {
        var heading = new TextBlock { Text = text, FontWeight = FontWeight.SemiBold, Classes = { "heading" } };
        App.UseBrush(heading, TextBlock.ForegroundProperty, App.HeaderBrushKey);
        return heading;
    }

    private static void AddRow(Grid grid, Control control, int row)
    {
        Grid.SetRow(control, row);
        grid.Children.Add(control);
    }

    // MARK: - Commands

    /// <summary>Sends a command, shows why if it was turned down, and redraws.</summary>
    private Reply Run(object command)
    {
        var reply = engine.Send(command);
        status.Text = reply.Ok ? "" : reply.Error;
        Refresh();
        return reply;
    }

    private void OnKey(object? sender, KeyEventArgs e)
    {
        if (IsTyping()) return;
        HandleKey(e);
    }

    /// <summary>Typing, and moving around an open menu or list of choices, keep their keys.</summary>
    private bool IsTyping() =>
        FocusManager?.GetFocusedElement() is TextBox or MenuItem or ComboBoxItem or ComboBox { IsDropDownOpen: true };

    /// <summary>The live keys, also used by the audience window.</summary>
    private void HandleKey(KeyEventArgs e)
    {
        object? command = (e.Key, e.KeyModifiers) switch
        {
            (Key.Right or Key.Down or Key.Space or Key.PageDown, KeyModifiers.None) => new { type = "next" },
            (Key.Left or Key.Up or Key.PageUp, KeyModifiers.None) => new { type = "previous" },
            (Key.F1, KeyModifiers.None) => new { type = "clearAll" },
            (Key.F2, KeyModifiers.None) => new { type = "clearSlide" },
            (Key.F3, KeyModifiers.None) => new { type = "clearBackground" },
            (Key.F4, KeyModifiers.None) => new { type = "blackout" },
            (Key.F5, KeyModifiers.None) => new { type = "restore" },
            (Key.Z, KeyModifiers.Control) => new { type = "undo" },
            (Key.Y, KeyModifiers.Control) or (Key.Z, KeyModifiers.Control | KeyModifiers.Shift) => new { type = "redo" },
            (Key.V or Key.C or Key.P or Key.B or Key.T or Key.I or Key.E or Key.N, KeyModifiers.None) =>
                new { type = "section", key = e.Key.ToString().ToLowerInvariant() },
            _ => null,
        };
        if (command is not null)
        {
            Run(command);
            e.Handled = true;
            return;
        }
        Action? action = (e.Key, e.KeyModifiers) switch
        {
            (Key.N, KeyModifiers.Control) => NewSong,
            (Key.I, KeyModifiers.Control) => ImportSongs,
            (Key.O, KeyModifiers.Control) => OpenProjectFile,
            (Key.E, KeyModifiers.Control) => ExportProject,
            (Key.F11, KeyModifiers.None) => ToggleOutput,
            (Key.OemComma, KeyModifiers.Control) => ShowSettings,
            _ => null,
        };
        if (action is null) return;
        action();
        e.Handled = true;
    }

    private async void NewSong()
    {
        var words = await Dialogs.Words(this, T("New Song"), "", "", T("Add Song"));
        if (words is not { } song) return;
        var reply = Run(new { type = "addSong", title = song.Title, text = song.Text });
        if (!reply.Ok) await Dialogs.Inform(this, T("The song wasn't added"), reply.Error ?? "");
    }

    private async void EditWords(Guid presentationID)
    {
        var words = engine.Send(new { type = "words", presentationID });
        if (!words.Ok)
        {
            status.Text = words.Error;
            return;
        }
        var edited = await Dialogs.Words(this, T("Edit Words"), words.GetString("title") ?? "", words.GetString("text") ?? "", T("Save"));
        if (edited is not { } song) return;
        var reply = Run(new { type = "editWords", presentationID, title = song.Title, text = song.Text });
        if (!reply.Ok) await Dialogs.Inform(this, T("The words weren't changed"), reply.Error ?? "");
    }

    private async void ImportSongs()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = T("Import Songs"),
            AllowMultiple = true,
            FileTypeFilter =
            [
                new FilePickerFileType(T("Song files (OpenLyrics, ProPresenter, ChordPro, SongSelect, text)"))
                {
                    Patterns = ["*.xml", "*.pro", "*.cho", "*.chordpro", "*.chopro", "*.crd", "*.txt", "*.usr"],
                },
                FilePickerFileTypes.All,
            ],
        });
        var paths = files.Select(f => f.TryGetLocalPath()).OfType<string>().ToArray();
        if (paths.Length == 0) return;
        var reply = Run(new { type = "importSongs", paths });
        var failures = reply.Failures();
        if (failures.Count == 0) return;
        var added = reply.GetInt("added");
        var lines = string.Join("\n", failures.Select(f => $"• {f.File}: {f.Reason}"));
        await Dialogs.Inform(this, T("Some files weren't imported"),
            (added == 1 ? T("1 song was added.") : T("{0} songs were added.", added)) + " " + T("These files weren't:") + "\n\n" + lines);
    }

    private async void RenamePresentation(Guid presentationID, string title)
    {
        var name = await Dialogs.Prompt(this, T("Rename"), T("Name"), title, T("Rename"));
        if (!string.IsNullOrWhiteSpace(name)) Run(new { type = "renamePresentation", presentationID, title = name });
    }

    private async void DeletePresentation(LibraryEntry entry)
    {
        var sure = await Dialogs.Confirm(this, T("Delete from the library?"),
            T("“{0}” is removed from the library and from every show. Edit › Undo brings it back.", entry.Title), T("Delete"));
        if (sure) Run(new { type = "deletePresentation", presentationID = entry.ID });
    }

    private async void NewShow()
    {
        var name = await Dialogs.Prompt(this, T("New Show"), T("Name"), "", T("Add Show"));
        if (name is not null) Run(new { type = "addShow", title = name });
    }

    private async void RenameShow()
    {
        var current = state.Shows.FirstOrDefault(s => s.ID == state.ActiveShowID)?.Title ?? "";
        var name = await Dialogs.Prompt(this, T("Rename Show"), T("Name"), current, T("Rename"));
        if (!string.IsNullOrWhiteSpace(name)) Run(new { type = "renameShow", showID = state.ActiveShowID, title = name });
    }

    private async void DeleteShow()
    {
        var current = state.Shows.FirstOrDefault(s => s.ID == state.ActiveShowID)?.Title ?? T("this show");
        var sure = await Dialogs.Confirm(this, T("Delete the show?"),
            T("“{0}” is deleted. Its songs stay in the library. Edit › Undo brings it back.", current), T("Delete"));
        if (sure) Run(new { type = "deleteShow", showID = state.ActiveShowID });
    }

    private async void OpenProjectFile()
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = T("Open Project File"),
            FileTypeFilter = [new FilePickerFileType(T("Presenter projects")) { Patterns = ["*.json"] }],
        });
        if (files.Count == 0 || files[0].TryGetLocalPath() is not { } path) return;
        var sure = await Dialogs.Confirm(this, T("Open this project?"),
            T("It replaces “{0}”, which is backed up first. What's on the audience output stays until you take another slide live.",
                state.ProjectName), T("Open"));
        if (!sure) return;
        var reply = Run(new { type = "openProject", path });
        if (reply.Ok)
        {
            Pictures.Forget();
            shownRevision = -1;
            Refresh();
            status.Text = T("Opened. The previous project was backed up to {0}", reply.GetString("backup"));
        }
        else
        {
            await Dialogs.Inform(this, T("The project wasn't opened"), reply.Error ?? "");
        }
    }

    private async void ExportProject()
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = T("Export Project"),
            SuggestedFileName = $"{state.ProjectName}.json",
            DefaultExtension = "json",
            FileTypeChoices = [new FilePickerFileType(T("Presenter project")) { Patterns = ["*.json"] }],
        });
        if (file?.TryGetLocalPath() is not { } path) return;
        var reply = Run(new { type = "exportProject", path });
        if (reply.Ok) status.Text = T("Exported to {0}. It opens in Presenter on a Mac or another PC, with its pictures.", path);
        else await Dialogs.Inform(this, T("The project wasn't exported"), reply.Error ?? "");
    }

    private async void ShowShortcuts()
    {
        await Dialogs.Inform(this, T("Keyboard Shortcuts"), string.Join("\n",
            T("→  ↓  Space  Page Down — next slide"),
            T("←  ↑  Page Up — previous slide"),
            T("V C P B T I E N — verse, chorus, pre-chorus, bridge, tag, intro, ending, interlude"),
            T("F1 — clear all"),
            T("F2 — clear slide"),
            T("F3 — clear background"),
            T("F4 — blackout"),
            T("F5 — restore output"),
            T("F11 — show or hide the audience output"),
            T("Ctrl+N — new song"),
            T("Ctrl+I — import songs"),
            T("Ctrl+Z / Ctrl+Y — undo / redo"),
            T("Ctrl+O / Ctrl+E — open / export a project file"),
            T("Ctrl+, — settings")));
    }

    private async void ShowAbout()
    {
        await Dialogs.Inform(this, T("About Presenter"),
            T("Presenter for Windows {0} (beta)", App.Version) + "\n" +
            T("Project format {0}, the same as Presenter 1.5 for Mac.", Engine.SchemaVersion) + "\n\n" +
            T("Your project is kept in {0}", engine.DataDirectory) + "\n\n" +
            T("Free and open source under the GPL-3.0 licence.") + "\n" +
            T("Problems and ideas: {0}", App.IssuesURL));
    }

    private void ShowSettings()
    {
        if (settingsWindow is not null)
        {
            settingsWindow.Activate();
            return;
        }
        // Restarting while something is on the audience output would take it off mid-service.
        settingsWindow = new SettingsWindow(() => output is not null && state.Audience is not null);
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Show(this);
    }

    // MARK: - The audience output

    private void FillDisplays()
    {
        var chosen = displayPicker.SelectedIndex;
        updating = true;
        displayPicker.Items.Clear();
        var screens = Screens.All;
        for (var index = 0; index < screens.Count; index++)
        {
            var screen = screens[index];
            var name = T("Display {0} — {1}×{2}", index + 1, screen.Bounds.Width, screen.Bounds.Height) + (screen.IsPrimary ? " " + T("(main)") : "");
            displayPicker.Items.Add(new ComboBoxItem { Content = name, Tag = screen });
        }
        displayPicker.Items.Add(new ComboBoxItem { Content = T("A window on this screen (to try things out)"), Tag = null });
        if (chosen < 0 || chosen >= displayPicker.Items.Count)
        {
            // The first display that isn't the main one, else the test window.
            var secondary = screens.ToList().FindIndex(s => !s.IsPrimary);
            chosen = secondary >= 0 ? secondary : screens.Count;
        }
        displayPicker.SelectedIndex = chosen;
        updating = false;
        UpdateOutputButton();
    }

    private void ToggleOutput()
    {
        if (output is not null)
        {
            output.Close();
            return;
        }
        if (displayPicker.SelectedItem is null) FillDisplays();
        var screen = (displayPicker.SelectedItem as ComboBoxItem)?.Tag as Screen;
        output = new OutputWindow(screen, HandleKey);
        output.Closed += (_, _) =>
        {
            output = null;
            UpdateOutputButton();
        };
        output.Display(state.Audience, state.Credits);
        output.Show();
        UpdateOutputButton();
        // Keys keep going to the operator window.
        Activate();
    }

    private void UpdateOutputButton()
    {
        outputButton.Content = output is null ? T("Show Audience Output (F11)") : T("Hide Audience Output (F11)");
        displayPicker.IsEnabled = output is null;
    }

    // MARK: - Redrawing

    private ItemInfo? SelectedItem() => state.Items.FirstOrDefault(i => i.ID == state.SelectedItemID);

    /// <summary>Reads the engine's state and redraws what changed.</summary>
    private void Refresh()
    {
        state = engine.State();
        updating = true;
        try
        {
            Title = $"Presenter (beta) — {state.ProjectName}";
            problemBar.IsVisible = state.Problem is not null;
            problemText.Text = state.Problem;
            undoItem.Header = state.UndoName is { } undo ? T("_Undo {0}", undo) : T("_Undo");
            undoItem.IsEnabled = state.UndoName is not null;
            redoItem.Header = state.RedoName is { } redo ? T("_Redo {0}", redo) : T("_Redo");
            redoItem.IsEnabled = state.RedoName is not null;

            var projectChanged = state.ProjectRevision != shownRevision || state.ActiveShowID != shownShow;
            if (projectChanged)
            {
                FillShows();
                FillItems();
                FillLibrary();
            }
            itemList.SelectedItem = itemList.Items.OfType<ListBoxItem>().FirstOrDefault(i => (i.Tag as ItemInfo)?.ID == state.SelectedItemID);
            if (projectChanged || state.SelectedItemID != shownItem) FillSlides();
            HighlightLive();

            if (state.AudienceKey != shownAudience)
            {
                audiencePreview.Child = new SlideView(state.Audience, state.Credits, checkerboard: false);
                output?.Display(state.Audience, state.Credits);
                shownAudience = state.AudienceKey;
            }
            if (state.IsBlackout) blackoutButton.Background = LiveBrush;
            else blackoutButton.ClearValue(BackgroundProperty);
            restoreButton.IsEnabled = state.CanRestore;

            shownRevision = state.ProjectRevision;
            shownShow = state.ActiveShowID;
            shownItem = state.SelectedItemID;
        }
        finally
        {
            updating = false;
        }
    }

    private void FillShows()
    {
        showPicker.Items.Clear();
        foreach (var show in state.Shows) showPicker.Items.Add(new ComboBoxItem { Content = show.Title, Tag = show.ID });
        showPicker.SelectedItem = showPicker.Items.OfType<ComboBoxItem>().FirstOrDefault(i => i.Tag is Guid id && id == state.ActiveShowID);
    }

    private void FillItems()
    {
        itemList.Items.Clear();
        for (var index = 0; index < state.Items.Count; index++)
        {
            var item = state.Items[index];
            var row = new DockPanel();
            var count = new TextBlock { Text = item.SlideCount.ToString(), Opacity = 0.5, Margin = new Thickness(8, 0, 0, 0) };
            DockPanel.SetDock(count, Dock.Right);
            row.Children.Add(count);
            row.Children.Add(new TextBlock { Text = (item.Kind == "song" ? "♪  " : "▭  ") + item.Title, TextTrimming = TextTrimming.CharacterEllipsis });

            var position = index;
            var listItem = new ListBoxItem { Content = row, Tag = item };
            listItem.ContextMenu = PopupMenu(
                Item(T("Edit Words…"), () => EditWords(item.PresentationID)),
                Item(T("Rename…"), () => RenamePresentation(item.PresentationID, item.Title)),
                new Separator(),
                Item(T("Move Up"), () => Run(new { type = "moveItem", itemID = item.ID, index = Math.Max(0, position - 1) })),
                Item(T("Move Down"), () => Run(new { type = "moveItem", itemID = item.ID, index = Math.Min(state.Items.Count - 1, position + 1) })),
                new Separator(),
                Item(T("Remove from Show"), () => Run(new { type = "removeItem", itemID = item.ID })));
            itemList.Items.Add(listItem);
        }
    }

    private void FillLibrary()
    {
        libraryList.Items.Clear();
        foreach (var entry in state.Library)
        {
            var row = new TextBlock { Text = (entry.Kind == "song" ? "♪  " : "▭  ") + entry.Title, TextTrimming = TextTrimming.CharacterEllipsis };
            var listItem = new ListBoxItem { Content = row, Tag = entry };
            listItem.DoubleTapped += (_, _) => Run(new { type = "addToShow", presentationID = entry.ID });
            listItem.ContextMenu = PopupMenu(
                Item(T("Add to Show"), () => Run(new { type = "addToShow", presentationID = entry.ID })),
                Item(T("Edit Words…"), () => EditWords(entry.ID)),
                Item(T("Rename…"), () => RenamePresentation(entry.ID, entry.Title)),
                new Separator(),
                Item(T("Delete from Library…"), () => DeletePresentation(entry)));
            libraryList.Items.Add(listItem);
        }
    }

    private static ContextMenu PopupMenu(params Control[] items)
    {
        var menu = new ContextMenu();
        foreach (var item in items) menu.Items.Add(item);
        return menu;
    }

    private void FillSlides()
    {
        slideGrid.Children.Clear();
        tiles.Clear();
        var item = SelectedItem();
        itemHeading.Text = item?.Title ?? "";
        editWordsButton.IsVisible = item is not null;
        emptyHint.IsVisible = state.Items.Count == 0;
        var number = 0;
        foreach (var entry in state.Slides)
        {
            number++;
            var thumbnail = new SlideView(entry.Slide, thumbnail: true) { Width = TileWidth, Height = TileHeight };
            var caption = new DockPanel { Margin = new Thickness(4, 4, 4, 2) };
            var index = new TextBlock { Text = number.ToString(), Opacity = 0.5, Classes = { "small" } };
            DockPanel.SetDock(index, Dock.Right);
            caption.Children.Add(index);
            if (!string.IsNullOrEmpty(entry.Label)) caption.Children.Add(SectionTag(entry.Label, entry.Section));
            var stack = new StackPanel();
            stack.Children.Add(thumbnail);
            stack.Children.Add(caption);
            var tile = new Border
            {
                Child = stack,
                Width = TileWidth + 6,
                Margin = new Thickness(0, 0, 10, 10),
                BorderThickness = new Thickness(3),
                CornerRadius = new CornerRadius(4),
                Cursor = new Cursor(StandardCursorType.Hand),
            };
            App.UseBrush(tile, Border.BackgroundProperty, App.PanelBrushKey);
            var position = entry.Position;
            tile.PointerPressed += (_, e) =>
            {
                if (!e.GetCurrentPoint(tile).Properties.IsLeftButtonPressed) return;
                Run(new { type = "takeLive", itemID = position.ItemID, slideID = position.SlideID, occurrence = position.Occurrence });
                e.Handled = true;
            };
            tiles[position] = tile;
            slideGrid.Children.Add(tile);
        }
    }

    private void HighlightLive()
    {
        foreach (var (position, tile) in tiles)
            tile.BorderBrush = position == state.Live ? LiveBrush : Brushes.Transparent;
    }

    /// <summary>
    /// A slide's group label ("Verse 1", "Coro") on a capsule in its section's colour, as on the Mac. The colours come
    /// from Settings, in the variant for the theme on screen.
    /// </summary>
    public static Control SectionTag(string label, string? section) => new Border
    {
        Background = new SolidColorBrush(Settings.Current.SectionColor(section, App.IsDark)),
        CornerRadius = new CornerRadius(9),
        Padding = new Thickness(7, 1),
        HorizontalAlignment = HorizontalAlignment.Left,
        Child = new TextBlock
        {
            Text = label,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Classes = { "small" },
        },
    };
}
