using System.Diagnostics;
using System.Reflection;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Styling;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;
using Presenter.Windows.Core;

namespace Presenter.Windows;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) => CrashLog.Write(e.ExceptionObject as Exception);
        return BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
    }

    public static AppBuilder BuildAvaloniaApp() => AppBuilder.Configure<App>().UsePlatformDetect().LogToTrace();
}

public sealed class App : Application
{
    public const string IssuesURL = "https://github.com/alps2005/PresenterApp/issues";

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
        RequestedThemeVariant = ThemeVariant.Dark;
    }

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
            ? "Part of Presenter is missing or couldn't load. Unzip the whole download again, keeping every file " +
              "together in one folder, and run Presenter.exe from there. If it still doesn't start, install the " +
              "Microsoft Visual C++ Redistributable (x64) from Microsoft's website and try again."
            : $"Presenter couldn't open its project folder, {dataDirectory}.";
        var body = new StackPanel { Spacing = 14, Margin = new Thickness(24) };
        body.Children.Add(new TextBlock { Text = "Presenter couldn't start", FontSize = 20, FontWeight = FontWeight.SemiBold });
        body.Children.Add(new TextBlock { Text = advice, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new SelectableTextBlock { Text = error.Message, TextWrapping = TextWrapping.Wrap, Opacity = 0.7 });
        var report = new Button { Content = "Report the problem", HorizontalAlignment = HorizontalAlignment.Left };
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
