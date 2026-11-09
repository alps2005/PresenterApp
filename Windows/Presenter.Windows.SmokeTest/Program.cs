using Presenter.Windows.Core;

// Runs the engine the way the app does, from a fresh folder, and exits 1 at the first thing that's wrong.
//
// It's a windowed program, like the app, so it has no standard output or error, like an app started by double-clicking.
// As a console program it couldn't see the engine's log line that brought the app down in betas 1 and 2. So it writes
// its results to a file beside it, line by line, to show how far it got if it dies.
var results = Path.Combine(AppContext.BaseDirectory, "smoke-results.txt");
File.WriteAllText(results, "");
void Report(string line) => File.AppendAllText(results, line + Environment.NewLine);

var failures = 0;
void Check(bool condition, string what)
{
    Report($"{(condition ? "ok  " : "FAIL")} {what}");
    if (!condition) failures++;
}

var root = Path.Combine(Path.GetTempPath(), "presenter-smoke-" + Guid.NewGuid());
var first = Path.Combine(root, "first");
try
{
    Check(Engine.SchemaVersion > 0, $"the engine loads (project format {Engine.SchemaVersion})");

    using (var engine = Engine.Open(first))
    {
        var state = engine.State();
        Check(state.Items.Count == 0 && state.Shows.Count == 1, "a new folder starts an empty project");

        var added = engine.Send(new { type = "addSong", title = "Canción de prueba", text = "Verse 1\nPrimera línea\n\nChorus\nCantamos juntos" });
        Check(added.Ok, "a song can be added");
        state = engine.State();
        Check(state.Items.Count == 1 && state.Items[0].Title == "Canción de prueba", "the song is in the show, accents intact");
        Check(state.Slides.Count == 2 && state.Slides[1].Section == "chorus", "the song has its verse and chorus");

        var slide = state.Slides[0].Position;
        Check(engine.Send(new { type = "takeLive", itemID = slide.ItemID, slideID = slide.SlideID, occurrence = slide.Occurrence }).Ok,
            "a slide goes live");
        Check(engine.Send(new { type = "next" }).Ok, "Next moves on");
        state = engine.State();
        Check(state.Audience?.Elements.FirstOrDefault()?.Text == "Cantamos juntos", "the audience sees the chorus");
        var end = engine.Send(new { type = "next" });
        Check(!end.Ok && !string.IsNullOrEmpty(end.Error), $"Next at the end says why ({end.Error})");
        Check(engine.Send(new { type = "blackout" }).Ok && engine.State().Audience is null, "Blackout hides everything");
        Check(engine.Send(new { type = "restore" }).Ok && engine.State().Audience is not null, "Restore brings it back");
        Check(engine.Send(new { type = "section", key = "v" }).Ok
            && engine.State().Audience?.Elements.FirstOrDefault()?.Text == "Primera línea", "the V key goes to the verse");

        var songs = Path.Combine(root, "songs");
        Directory.CreateDirectory(songs);
        var chordPro = Path.Combine(songs, "Grace.cho");
        File.WriteAllText(chordPro, "{title: Grace}\n{start_of_verse}\n[G]Amazing grace\n{end_of_verse}\n");
        var imported = engine.Send(new { type = "importSongs", paths = new[] { chordPro, Path.Combine(songs, "missing.txt") } });
        Check(imported.Ok && imported.GetInt("added") == 1 && imported.Failures().Count == 1, "song files import, and a missing one is listed");

        Check(engine.Send(new { type = "exportProject", path = Path.Combine(root, "export.json") }).Ok, "the project exports");

        var wrongThread = false;
        var thread = new Thread(() =>
        {
            try { engine.State(); }
            catch (InvalidOperationException) { wrongThread = true; }
        });
        thread.Start();
        thread.Join();
        Check(wrongThread, "the engine refuses calls from another thread");
    }

    using (var engine = Engine.Open(first))
    {
        Check(engine.State().Items.Count == 2, "the project is saved and opens again");
    }

    Engine.SetLanguage("es");
    using (var engine = Engine.Open(Path.Combine(root, "spanish")))
    {
        var state = engine.State();
        Check(state.Shows.FirstOrDefault()?.Title == "Culto", $"in Spanish, a new project's show is named in Spanish ({state.Shows.FirstOrDefault()?.Title})");
        var nothing = engine.Send(new { type = "next" });
        Check(nothing.Error == "No hay nada en vivo.", $"in Spanish, the engine explains itself in Spanish ({nothing.Error})");
    }
    Engine.SetLanguage("en");

    using (var engine = Engine.Open(Path.Combine(root, "second")))
    {
        var opened = engine.Send(new { type = "openProject", path = Path.Combine(root, "export.json") });
        Check(opened.Ok && engine.State().Library.Count == 2, "an exported project opens in another folder");
        Check(File.Exists(opened.GetString("backup")), "the project it replaced was backed up");
    }
}
catch (Exception error)
{
    Report($"FAIL {error}");
    failures++;
}
finally
{
    try { Directory.Delete(root, recursive: true); } catch (IOException) { }
}

Report(failures == 0 ? "All checks passed." : $"{failures} checks failed.");
return failures == 0 ? 0 : 1;
