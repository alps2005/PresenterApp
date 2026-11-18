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

    using (var engine = Engine.Open(Path.Combine(root, "bibles")))
    {
        // Bible XML is read by Foundation on Windows too, which parses differently from the Mac's (XMLParsing.swift).
        var bibleFile = Path.Combine(root, "rvr.xml");
        File.WriteAllText(bibleFile, """
            <?xml version="1.0" encoding="UTF-8"?>
            <XMLBIBLE biblename="Reina-Valera 1909">
              <INFORMATION><title>Reina-Valera 1909</title><identifier>RVR1909</identifier><language>SPA</language></INFORMATION>
              <BIBLEBOOK bnumber="43" bname="Juan"><CHAPTER cnumber="3">
                <VERS vnumber="16">Porque de tal manera amó Dios al mundo.</VERS>
                <VERS vnumber="17">Porque no envió Dios á su Hijo al mundo.</VERS>
              </CHAPTER></BIBLEBOOK>
            </XMLBIBLE>
            """);
        var bible = engine.Send(new { type = "importBible", paths = new[] { bibleFile } });
        Check(bible.Ok, $"a Bible file imports ({bible.Error})");
        var bibleID = bible.GetString("bibleID");
        Check(File.Exists(Path.Combine(root, "bibles", "Bibles", "index.json")), "Bibles are kept beside the project");
        var found = engine.Send(new { type = "lookUpScripture", bibleID, text = "Juan 3:16-17" });
        Check(found.Ok && found.GetString("caption") == "Juan 3:16-17 · RVR1909", $"a reference is looked up ({found.GetString("caption") ?? found.Error})");
        var missing = engine.Send(new { type = "lookUpScripture", bibleID, text = "Juan 3:40" });
        Check(!missing.Ok && missing.Error == "Juan 3 no tiene versículo 40.", $"a verse that isn't there says why, in the Bible's language ({missing.Error})");
        // eBible.org's Reina-Valera 1909 starts with a UTF-8 byte-order mark, as files saved by Windows tools often do.
        var marked = Path.Combine(root, "marked.xml");
        File.WriteAllText(marked, File.ReadAllText(bibleFile), new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        var markedBible = engine.Send(new { type = "importBible", paths = new[] { marked } });
        Check(markedBible.Ok, $"a Bible file that starts with a byte-order mark imports ({markedBible.Error})");
        var song = Path.Combine(root, "marked-song.xml");
        File.WriteAllText(song, """
            <?xml version="1.0" encoding="UTF-8"?>
            <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.8">
              <properties><titles><title>Con marca</title></titles></properties>
              <lyrics><verse name="v1"><lines>Primera línea</lines></verse></lyrics>
            </song>
            """, new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
        var markedSong = engine.Send(new { type = "importSongs", paths = new[] { song } });
        Check(markedSong.Ok && markedSong.GetInt("added") == 1, $"an OpenLyrics song that starts with a byte-order mark imports ({string.Join("; ", markedSong.Failures().Select(f => f.Reason))})");
        var broken = Path.Combine(root, "broken.xml");
        File.WriteAllText(broken, "<XMLBIBLE><BIBLEBOOK bnumber=\"43\"><CHAPTER cnumber=\"3\"><VERS vnumber=\"16\">Sin cerrar");
        Check(!engine.Send(new { type = "importBible", paths = new[] { broken } }).Ok, "a damaged Bible file is turned down");
        Check(engine.Send(new { type = "addScripture", bibleID, text = "Juan 3:16-17", versesPerSlide = 1 }).Ok, "a passage is added to the show");
        var state = engine.State();
        Check(state.Items.Count(i => i.Kind == "scripture") == 1 && state.Slides.Count == 2,
            $"the passage is in the show, a verse per slide ({state.Slides.Count} slides)");
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
