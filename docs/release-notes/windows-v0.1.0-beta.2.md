The second beta of **Presenter for Windows**. It now has a proper installer, the same icon as the Mac app, Settings and Spanish, and a fix for a bug that could close the audience output mid-song.

This is still an early beta. Please try it at a rehearsal before using it in a service, and [tell us](https://github.com/alps2005/PresenterApp/issues) what goes wrong or what you miss.

## Install

1. Download **Presenter-Windows-0.1.0-beta.2-Setup.exe** below and double-click it.
2. The app isn't code-signed yet, so Windows says **"Windows protected your PC"**. Click **More info**, then **Run anyway**.
3. Presenter installs for the person signed in, adds itself to the Start menu and the Desktop, and opens.

Needs Windows 10 or 11 (64-bit). Nothing else to install: the app carries what it needs.

**Coming from beta 1?** Close it and run the installer. Your project carries over, because it's kept separately in `%LOCALAPPDATA%\Presenter`. You can then delete the old unzipped folder.

There are no automatic updates in the beta. To move to a new version, close Presenter and run the new installer. To remove Presenter, use **Windows Settings › Apps › Installed apps**. Your project stays on the computer either way; delete that folder yourself if you want it gone too.

## What's new

- **An installer instead of a zip:** no folder to unzip and keep together.
- **The same icon as the Mac app:** on the shortcuts, the installer and the windows.
- **Settings (File › Settings…, Ctrl+,):** dark, light or the same as Windows; the text size on the operator screen (slides and outputs keep theirs); and the colours for LIVE and each kind of song section, with Restore Defaults. They're kept on that computer, not in the project.
- **Presenter in Spanish:** every window, menu and message. Settings › Language chooses English, Español or the same as Windows, and applies the next time Presenter opens. **Restart Presenter Now** does that straight away.

## Fixes

- **Space after clicking a button:** Space moved to the next slide *and* pressed the button clicked last, which could close the audience output mid-song. Space now only moves on.

## Not in this beta yet

Videos and audio don't play (a slide with a video background shows black behind its words), and there are no Bibles, slide editor, themes, stage display, timers, messages or update checks yet. Pictures in HEIC format don't show. These come in later betas, starting with what testers ask for most.

## Reporting a problem

Use [GitHub Issues](https://github.com/alps2005/PresenterApp/issues) and say what you did and what happened. If something went wrong inside the app, it wrote a file in `%LOCALAPPDATA%\Presenter\Logs` (**Help › Open the Problem Logs Folder**): please attach it.
