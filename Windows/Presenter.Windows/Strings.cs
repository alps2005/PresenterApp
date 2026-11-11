namespace Presenter.Windows;

/// <summary>
/// The app's words in the operator's language. The English is the key; Spanish comes from <see cref="SpanishStrings"/>,
/// with the same glossary as the Mac app and the engine (programa, diapositiva, en vivo, salida al público). The
/// language is read once at launch, like the Mac app, so a change in Settings applies after a restart.
/// </summary>
public static class Strings
{
    public static bool IsSpanish { get; } = Settings.Current.IsSpanish;

    /// <summary>The engine's language code, for <c>Engine.SetLanguage</c>.</summary>
    public static string LanguageCode => IsSpanish ? "es" : "en";

    /// <summary>
    /// <paramref name="english"/> in the current language, with {0}, {1}… filled in after translating, so a translation can
    /// put them where its grammar needs them.
    /// </summary>
    public static string T(string english, params object?[] arguments)
    {
        var text = IsSpanish && SpanishStrings.Table.TryGetValue(english, out var spanish) ? spanish : english;
        return arguments.Length == 0 ? text : string.Format(text, arguments);
    }
}
