using System.Diagnostics;
using System.Reflection;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Controls.Primitives;
using Avalonia.Layout;
using Avalonia.Markup.Xaml.Styling;
using Avalonia.Media;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;
using Presenter.Windows.Core;
using static Presenter.Windows.Strings;

namespace Presenter.Windows;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) => CrashLog.Write(e.ExceptionObject as Exception);
        var result = BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        // Settings › Restart Presenter Now: started again once this copy has saved and closed its project.
        if (App.RestartWhenClosed && Environment.ProcessPath is { } path)
        {
            try
            {
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = false, Arguments = string.Join(" ", args.Select(a => $"\"{a}\"")) });
            }
            catch (Exception error)
            {
                CrashLog.Write(error);
            }
        }
        return result;
    }

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}

public sealed class App : Application
{
    public const string IssuesURL = "https://github.com/alps2005/PresenterApp/issues";

    /// <summary>Set by Settings › Restart Presenter Now: Presenter opens again after it closes.</summary>
    public static bool RestartWhenClosed { get; set; }

    // Colours that differ between the dark and light themes, looked up by key so they follow a change of theme.
    public const string PanelBrushKey = "PresenterPanelBrush";
    public const string HeaderBrushKey = "PresenterHeaderBrush";
    public const string ProblemBrushKey = "PresenterProblemBrush";

    /// <summary>Whether the theme on screen is dark, for colours that come in a dark and a light version.</summary>
    public static bool IsDark => Current?.ActualThemeVariant != ThemeVariant.Light;

    /// <summary>Keeps a property set to a theme colour, also when the theme changes.</summary>
    public static void UseBrush(Control control, AvaloniaProperty property, string key) =>
        control.Bind(property, control.GetResourceObservable(key));

    private Styles? lookStyles;

    /// <summary>"0.1.0-beta.1", from the build.</summary>
    public static string Version
    {
        get
        {
            var version = typeof(App).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion ?? "?";
            var plus = version.IndexOf('+');
            return plus < 0 ? version : version[..plus];
        }
    }

    /// <summary>Where the project lives: %LOCALAPPDATA%\Presenter, or the folder after --data.</summary>
    public static string DataDirectory(string[] args)
    {
        var index = Array.IndexOf(args, "--data");
        if (index >= 0 && index + 1 < args.Length) return Path.GetFullPath(args[index + 1]);
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Presenter");
    }

    public static void OpenInShell(string target)
    {
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // Nothing to open it with; the path or address is shown where it was offered.
        }
    }

    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        // The colour picker in Settings brings its own look.
        Styles.Add(new StyleInclude(new Uri("avares://Presenter/"))
        {
            Source = new Uri("avares://Avalonia.Controls.ColorPicker/Themes/Fluent/Fluent.xaml"),
        });
        Resources.ThemeDictionaries[ThemeVariant.Dark] = new ResourceDictionary
        {
            [PanelBrushKey] = new SolidColorBrush(Color.FromRgb(28, 28, 32)),
            [HeaderBrushKey] = new SolidColorBrush(Color.FromRgb(150, 150, 160)),
            [ProblemBrushKey] = new SolidColorBrush(Color.FromRgb(92, 74, 0)),
        };
        Resources.ThemeDictionaries[ThemeVariant.Light] = new ResourceDictionary
        {
            [PanelBrushKey] = new SolidColorBrush(Color.FromRgb(236, 236, 240)),
            [HeaderBrushKey] = new SolidColorBrush(Color.FromRgb(105, 105, 115)),
            [ProblemBrushKey] = new SolidColorBrush(Color.FromRgb(255, 236, 170)),
        };
        ApplyLook();
        Settings.Changed += ApplyLook;
    }

    /// <summary>Puts Settings' appearance and text size on every window, straight away.</summary>
    private void ApplyLook()
    {
        var settings = Settings.Current;
        RequestedThemeVariant = settings.Appearance switch
        {
            AppearanceChoice.Light => ThemeVariant.Light,
            AppearanceChoice.System => ThemeVariant.Default,
            _ => ThemeVariant.Dark,
        };

        // Text size: the controls' own size (a Fluent theme resource), the windows' text, and the app's few sizes.
        var scale = settings.TextScale;
        Resources["ControlContentThemeFontSize"] = 14 * scale;
        if (lookStyles is not null) Styles.Remove(lookStyles);
        lookStyles = new Styles
        {
            FontSize(x => x.OfType<Window>(), TemplatedControl.FontSizeProperty, 14 * scale),
            FontSize(x => x.OfType<TextBlock>().Class("title"), TextBlock.FontSizeProperty, 18 * scale),
            FontSize(x => x.OfType<TextBlock>().Class("small"), TextBlock.FontSizeProperty, 12 * scale),
            FontSize(x => x.OfType<TextBlock>().Class("heading"), TextBlock.FontSizeProperty, 11 * scale),
            FontSize(x => x.OfType<TextBlock>().Class("tiny"), TextBlock.FontSizeProperty, 11 * scale),
        };
        Styles.Add(lookStyles);
    }

    private static Style FontSize(Func<Selector?, Selector> selector, AvaloniaProperty property, double size) =>
        new(selector) { Setters = { new Setter(property, size) } };

    public override void OnFrameworkInitializationCompleted()
    {
        // A mistake in the app shouldn't end a service: it's written down and the operator carries on.
        Dispatcher.UIThread.UnhandledException += (_, e) =>
        {
            CrashLog.Write(e.Exception);
            e.Handled = true;
        };

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var dataDirectory = DataDirectory(desktop.Args ?? []);
            try
            {
                // The engine's messages and a new project's names in the operator's language.
                Engine.SetLanguage(LanguageCode);
                desktop.MainWindow = new MainWindow(Engine.Open(dataDirectory));
            }
            catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException
                                              or InvalidOperationException or IOException or UnauthorizedAccessException)
            {
                CrashLog.Write(error);
                desktop.MainWindow = StartupProblem(error, dataDirectory);
            }
        }
        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>Shown instead of the operator window when the engine can't start.</summary>
    private static Window StartupProblem(Exception error, string dataDirectory)
    {
        var advice = error is DllNotFoundException or BadImageFormatException
            ? T("Part of Presenter is missing or couldn't load. Unzip the whole download again, keeping every file " +
                "together in one folder, and run Presenter.exe from there. If it still doesn't start, install the " +
                "Microsoft Visual C++ Redistributable (x64) from Microsoft's website and try again.")
            : T("Presenter couldn't open its project folder, {0}.", dataDirectory);
        var body = new StackPanel { Spacing = 14, Margin = new Thickness(24) };
        body.Children.Add(new TextBlock { Text = T("Presenter couldn't start"), FontSize = 20, FontWeight = FontWeight.SemiBold });
        body.Children.Add(new TextBlock { Text = advice, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new SelectableTextBlock { Text = error.Message, TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        var report = new Button { Content = T("Report the problem"), HorizontalAlignment = HorizontalAlignment.Left };
        report.Click += (_, _) => OpenInShell(IssuesURL);
        body.Children.Add(report);
        return new Window { Title = "Presenter", Width = 560, SizeToContent = SizeToContent.Height, Content = body };
    }
}

/// <summary>Writes what went wrong to %LOCALAPPDATA%\Presenter\Logs, to attach to a problem report.</summary>
public static class CrashLog
{
    public static string Directory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Presenter", "Logs");

    public static void Write(Exception? error)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var file = Path.Combine(Directory, $"problem-{DateTime.Now:yyyy-MM-dd-HHmmss}.txt");
            File.WriteAllText(file, $"Presenter {App.Version} on {Environment.OSVersion}\n\n{error}\n");
        }
        catch (Exception)
        {
            // Nowhere to write it.
        }
    }
}
