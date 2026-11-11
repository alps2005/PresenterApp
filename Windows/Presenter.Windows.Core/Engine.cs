using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Presenter.Windows.Core;

/// <summary>
/// The shared Presenter engine, loaded from PresenterBridge.dll (Packages/PresenterBridge). Commands go in as JSON
/// and the state comes back as JSON; see BridgeSession.swift for the commands and BridgeState.swift for the state.
/// </summary>
/// <remarks>
/// The engine isn't thread-safe: every call must come from the thread that opened it (the UI thread).
/// </remarks>
public sealed class Engine : IDisposable
{
    private const string Library = "PresenterBridge";

    [DllImport(Library, EntryPoint = "presenter_open", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr NativeOpen([MarshalAs(UnmanagedType.LPUTF8Str)] string dataDirectory);

    [DllImport(Library, EntryPoint = "presenter_send", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr NativeSend(IntPtr handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string command);

    [DllImport(Library, EntryPoint = "presenter_state", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr NativeState(IntPtr handle);

    [DllImport(Library, EntryPoint = "presenter_tick", CallingConvention = CallingConvention.Cdecl)]
    private static extern int NativeTick(IntPtr handle);

    [DllImport(Library, EntryPoint = "presenter_close", CallingConvention = CallingConvention.Cdecl)]
    private static extern void NativeClose(IntPtr handle);

    [DllImport(Library, EntryPoint = "presenter_free", CallingConvention = CallingConvention.Cdecl)]
    private static extern void NativeFree(IntPtr text);

    [DllImport(Library, EntryPoint = "presenter_set_language", CallingConvention = CallingConvention.Cdecl)]
    private static extern void NativeSetLanguage([MarshalAs(UnmanagedType.LPUTF8Str)] string code);

    [DllImport(Library, EntryPoint = "presenter_schema_version", CallingConvention = CallingConvention.Cdecl)]
    private static extern int NativeSchemaVersion();

    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private IntPtr handle;
    private readonly int thread = Environment.CurrentManagedThreadId;

    private Engine(IntPtr handle, string dataDirectory)
    {
        this.handle = handle;
        DataDirectory = dataDirectory;
    }

    /// <summary>Where the project, its media and its backups live.</summary>
    public string DataDirectory { get; }

    /// <summary>The project format the engine reads and writes (the Mac app's ProjectDocument.currentSchemaVersion).</summary>
    public static int SchemaVersion => NativeSchemaVersion();

    /// <summary>
    /// The language the engine's messages, undo names and new things' names are in ("en" or "es"). Set before
    /// <see cref="Open"/>, so a new project's first show is named in it too.
    /// </summary>
    public static void SetLanguage(string code) => NativeSetLanguage(code);

    /// <summary>
    /// Opens the project in <paramref name="dataDirectory"/>, creating the folder if needed. Throws
    /// DllNotFoundException when PresenterBridge.dll (or the Swift runtime beside it) can't be loaded.
    /// </summary>
    public static Engine Open(string dataDirectory)
    {
        Directory.CreateDirectory(dataDirectory);
        var handle = NativeOpen(dataDirectory);
        if (handle == IntPtr.Zero) throw new InvalidOperationException("The engine couldn't open the project folder.");
        return new Engine(handle, dataDirectory);
    }

    /// <summary>Runs a command: an object with a "type" and the fields that command needs.</summary>
    public Reply Send(object command)
    {
        var json = TakeString(NativeSend(Handle(), JsonSerializer.Serialize(command, Json)));
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement.Clone();
        var ok = root.TryGetProperty("ok", out var value) && value.ValueKind == JsonValueKind.True;
        var error = root.TryGetProperty("error", out var message) ? message.GetString() : null;
        return new Reply(ok, error, root);
    }

    /// <summary>Everything the app draws.</summary>
    public EngineState State()
    {
        var json = TakeString(NativeState(Handle()));
        var state = JsonSerializer.Deserialize<EngineState>(json, Json) ?? throw new InvalidOperationException("The engine sent no state.");
        // Kept as text too, so the audience output is redrawn only when what it shows has changed.
        using var document = JsonDocument.Parse(json);
        state.AudienceKey = (document.RootElement.TryGetProperty("audience", out var audience) ? audience.GetRawText() : "black")
            + "|" + state.Credits;
        return state;
    }

    /// <summary>Moves the live slide on when its countdown ends. True when the state should be read again.</summary>
    public bool Tick() => NativeTick(Handle()) != 0;

    /// <summary>Saves anything unsaved and closes the project.</summary>
    public void Dispose()
    {
        if (handle == IntPtr.Zero) return;
        CheckThread();
        NativeClose(handle);
        handle = IntPtr.Zero;
    }

    private IntPtr Handle()
    {
        CheckThread();
        if (handle == IntPtr.Zero) throw new ObjectDisposedException(nameof(Engine));
        return handle;
    }

    private void CheckThread()
    {
        if (Environment.CurrentManagedThreadId != thread)
            throw new InvalidOperationException("The engine is used only from the thread that opened it.");
    }

    private static string TakeString(IntPtr text)
    {
        if (text == IntPtr.Zero) throw new InvalidOperationException("The engine gave no answer.");
        try
        {
            return Marshal.PtrToStringUTF8(text) ?? "";
        }
        finally
        {
            NativeFree(text);
        }
    }
}

/// <summary>The engine's answer to a command. <see cref="Values"/> holds the whole reply.</summary>
public sealed record Reply(bool Ok, string? Error, JsonElement Values)
{
    public string? GetString(string name) =>
        Values.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    public int GetInt(string name) =>
        Values.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt32() : 0;

    /// <summary>The files an import couldn't read, with why.</summary>
    public IReadOnlyList<(string File, string Reason)> Failures()
    {
        if (!Values.TryGetProperty("failures", out var list) || list.ValueKind != JsonValueKind.Array) return [];
        return list.EnumerateArray()
            .Select(f => (f.GetProperty("file").GetString() ?? "", f.GetProperty("reason").GetString() ?? ""))
            .ToList();
    }
}
