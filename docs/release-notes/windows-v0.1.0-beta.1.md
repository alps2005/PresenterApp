> ⚠️ **Don't use this beta in a service.** Presenter can close as soon as you click a slide to show it. Your project isn't lost. **Fixed in [beta 4](https://github.com/alps2005/PresenterApp/releases/tag/windows-v0.1.0-beta.4): please use that instead.**

The first beta of **Presenter for Windows**, for churches whose computers are PCs. It runs on the same engine as Presenter for Mac, so songs, shows and live control behave the same, and projects move between the two.

This is an early beta. Please try it at a rehearsal before using it in a service, and [tell us](https://github.com/alps2005/PresenterApp/issues) what goes wrong or what you miss.

## Install

1. Download **Presenter-Windows-0.1.0-beta.1.zip** below and unzip the whole folder somewhere of its own, such as Documents. Keep every file together.
2. Double-click **Presenter.exe** in that folder.
3. The app isn't code-signed yet, so the first time Windows says **"Windows protected your PC"**. Click **More info**, then **Run anyway**.

Needs Windows 10 or 11 (64-bit). Nothing else to install: the app carries what it needs. If it says a file is missing, install the Microsoft Visual C++ Redistributable (x64) from Microsoft's website.

There are no automatic updates in the beta. To update, download the new zip and replace the folder: your project is kept separately, in `%LOCALAPPDATA%\Presenter`.

## What it does

- **Songs:** type or paste the words (**Show › New Song…**, Ctrl+N). A blank line starts a new slide, and a line like *Verse 1*, *Chorus*, *Coro* or *Puente* names the slides after it. Or import song files (**Show › Import Songs…**, Ctrl+I): OpenLyrics, ProPresenter 7 (.pro), ChordPro, SongSelect (.txt and .usr) and plain text. **Edit Words…** changes a song's words later.
- **Shows:** build the order of service from the library (double-click a song to add it), reorder or remove items with a right-click, and keep several shows (**Show › New Show…**).
- **Live:** click a slide to show it, or use → and Space for the next slide and ← for the previous one. F1 clears everything, F2 the words, F3 the background, F4 blacks out the screen and F5 brings it back. The section keys V, C, P, B, T, I, E and N jump to a song's verse, chorus, pre-chorus, bridge, tag, intro, ending or interlude; press again for the next one.
- **Audience output:** opens full screen on the second display or projector. On a computer with one screen it opens in a window, so you can try things out. F11 shows or hides it.
- **Projects from a Mac:** in Presenter for Mac, choose **File › Export Project…**; on the PC, choose **File › Open Project File…**. The slides come with their pictures, colours and layout, and their fonts when the PC has them. It works the other way too.
- **Safe saving:** everything is saved as you go, and the project is backed up when the app opens and before another project replaces it. **Edit › Undo** (Ctrl+Z) takes back changes to songs and shows.

## Not in this beta yet

Videos and audio don't play (a slide with a video background shows black behind its words), and there are no Bibles, slide editor, themes, stage display, timers, messages or update checks yet. Pictures in HEIC format don't show. These come in later betas, starting with what testers ask for most.

## Reporting a problem

Use [GitHub Issues](https://github.com/alps2005/PresenterApp/issues) and say what you did and what happened. If something went wrong inside the app, it wrote a file in `%LOCALAPPDATA%\Presenter\Logs` (**Help › Open the Problem Logs Folder**): please attach it.
