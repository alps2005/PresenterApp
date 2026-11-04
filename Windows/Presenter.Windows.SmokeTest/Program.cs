using Presenter.Windows.Core;

// Runs the engine the way the app does, from a fresh folder, and exits 1 at the first thing that's wrong.
var failures = 0;
void Check(bool condition, string what)
{
    Console.WriteLine($"{(condition ? "ok  " : "FAIL")} {what}");
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

        var added = engine.Send(new { type = "addSong", title = "Canción de prueba", text = "Verse 1\nPrimera línea\n\nChorus\nCoro" });
        Check(added.Ok, "a song can be added");
        state = engine.State();
        Check(state.Items.Count == 1 && state.Items[0].Title == "Canción de prueba", "the song is in the show, accents intact");
        Check(state.Slides.Count == 2 && state.Slides[1].Section == "chorus", "the song has its verse and chorus");

        var slide = state.Slides[0].Position;
        Check(engine.Send(new { type = "takeLive", itemID = slide.ItemID, slideID = slide.SlideID, occurrence = slide.Occurrence }).Ok,
            "a slide goes live");
        Check(engine.Send(new { type = "next" }).Ok, "Next moves on");
        state = engine.State();
        Check(state.Audience?.Elements.FirstOrDefault()?.Text == "Coro", "the audience sees the chorus");
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

    using (var engine = Engine.Open(Path.Combine(root, "second")))
    {
        var opened = engine.Send(new { type = "openProject", path = Path.Combine(root, "export.json") });
        Check(opened.Ok && engine.State().Library.Count == 2, "an exported project opens in another folder");
        Check(File.Exists(opened.GetString("backup")), "the project it replaced was backed up");
    }
}
catch (Exception error)
{
    Console.WriteLine($"FAIL {error}");
    failures++;
}
finally
{
    try { Directory.Delete(root, recursive: true); } catch (IOException) { }
}

Console.WriteLine(failures == 0 ? "All checks passed." : $"{failures} checks failed.");
return failures == 0 ? 0 : 1;
