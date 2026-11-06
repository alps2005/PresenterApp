using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Avalonia.Media;

namespace Presenter.Windows;

public enum AppearanceChoice { Dark, Light, System }

public enum TextSizeChoice { Small, Standard, Large, ExtraLarge }

public enum LanguageChoice { System, English, Spanish }

/// <summary>
/// How Presenter looks on this PC: appearance, text size, language and the colours for LIVE and each kind of song
/// section. Kept in %APPDATA%\Presenter\settings.json, not in the project, so moving a project never changes anyone's
/// screen. The Mac app has the same settings and the same default colours (Presenter/Settings/AppSettings.swift).
/// </summary>
public sealed class Settings
{
    public AppearanceChoice Appearance { get; set; } = AppearanceChoice.Dark;
    public TextSizeChoice TextSize { get; set; } = TextSizeChoice.Standard;
    public LanguageChoice Language { get; set; } = LanguageChoice.System;
    /// <summary>"#RRGGBB", or null for the default.</summary>
    public string? LiveColor { get; set; }
    /// <summary>Colours the operator chose, by section key ("verse", "preChorus"…). Missing keys use the default.</summary>
    public Dictionary<string, string> SectionColors { get; set; } = [];

    /// <summary>Raised after any change, so open windows redraw.</summary>
    public static event Action? Changed;

    public static Settings Current { get; private set; } = Load();

    public static string FilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Presenter", "settings.json");

    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    private static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Json) ?? new Settings();
        }
        catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException)
        {
            // A damaged settings file only costs the operator their choices, never the start of a service.
            CrashLog.Write(error);
        }
        return new Settings();
    }

    /// <summary>Saves and tells open windows. A failure to save is written to the problem log and otherwise ignored.</summary>
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Json));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            CrashLog.Write(error);
        }
        Changed?.Invoke();
    }

    /// <summary>Puts appearance, text size and every colour back. The language is left as it is.</summary>
    public void ResetLook()
    {
        Appearance = AppearanceChoice.Dark;
        TextSize = TextSizeChoice.Standard;
        LiveColor = null;
        SectionColors.Clear();
        Save();
    }

    [JsonIgnore]
    public bool IsLookCustomized =>
        Appearance != AppearanceChoice.Dark || TextSize != TextSizeChoice.Standard || LiveColor is not null || SectionColors.Count > 0;

    // MARK: - Derived values

    [JsonIgnore]
    public double TextScale => TextSize switch
    {
        TextSizeChoice.Small => 0.9,
        TextSizeChoice.Large => 1.15,
        TextSizeChoice.ExtraLarge => 1.3,
        _ => 1,
    };

    /// <summary>The language the screens are in: the chosen one, else Windows' display language if it's Spanish.</summary>
    [JsonIgnore]
    public bool IsSpanish => Language switch
    {
        LanguageChoice.Spanish => true,
        LanguageChoice.English => false,
        _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "es",
    };

    [JsonIgnore]
    public Color Live => Parse(LiveColor) ?? DefaultLive;

    public Color SectionColor(string? section, bool dark)
    {
        var key = section ?? "other";
        return SectionColors.TryGetValue(key, out var hex) && Parse(hex) is { } chosen ? chosen : DefaultSectionColor(key, dark);
    }

    public void SetSectionColor(string section, Color color)
    {
        SectionColors[section] = Hex(color);
        Save();
    }

    public void SetLiveColor(Color color)
    {
        LiveColor = Hex(color);
        Save();
    }

    // MARK: - Defaults, the same as the Mac app's

    /// <summary>LIVE red: never an accent colour, so it can't be mistaken for anything else.</summary>
    public static readonly Color DefaultLive = Color.FromRgb(0xEB, 0x33, 0x2E);

    /// <summary>The section kinds in the order Settings lists them, with their English names (see <see cref="Strings"/>).</summary>
    public static readonly (string Key, string Name)[] SectionKinds =
    [
        ("verse", "Verse"), ("preChorus", "Pre-Chorus"), ("chorus", "Chorus"), ("bridge", "Bridge"), ("tag", "Tag"),
        ("intro", "Intro"), ("ending", "Ending"), ("interlude", "Interlude"), ("other", "Other labels"),
    ];

    /// <summary>macOS's indigo, teal, purple, brown, pink, cyan and grey, as the Mac app shows them in each appearance.</summary>
    public static Color DefaultSectionColor(string key, bool dark) => Color.Parse(key switch
    {
        "verse" => dark ? "#6D7CFF" : "#6155F5",
        "preChorus" => dark ? "#00D2E0" : "#00C3D0",
        "chorus" => dark ? "#DB34F2" : "#CB30E0",
        "bridge" => dark ? "#B78A66" : "#AC7F5E",
        "tag" or "ending" => dark ? "#FF375F" : "#FF2D55",
        "intro" or "interlude" => dark ? "#3CD3FE" : "#00C0E8",
        _ => dark ? "#98989D" : "#8E8E93",
    });

    public static string Hex(Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    private static Color? Parse(string? hex) => hex is not null && Color.TryParse(hex, out var color) ? color : null;
}
