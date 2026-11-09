The third beta of **Presenter for Windows**. **Please update if you have beta 1 or beta 2:** in those, Presenter could close as soon as you added a song or clicked a slide to show it. This beta fixes that, and your settings now stay when Presenter closes.

This is still an early beta. Please try it at a rehearsal before using it in a service, and [tell us](https://github.com/alps2005/PresenterApp/issues) what goes wrong or what you miss.

## Install

1. Download **Presenter-Windows-0.1.0-beta.3-Setup.exe** below and double-click it.
2. The app isn't code-signed yet, so Windows may say **"Windows protected your PC"**. Click **More info**, then **Run anyway**.
3. Presenter installs for the person signed in, adds itself to the Start menu and the Desktop, and opens.

Needs Windows 10 or 11 (64-bit). Nothing else to install: the app carries what it needs.

**Coming from beta 2?** Close Presenter and run the installer. It says Presenter is already installed: click **Update**.

**Coming from beta 1?** Close it and run the installer. You can then delete the old unzipped folder.

Your project carries over either way, because it's kept separately in `%LOCALAPPDATA%\Presenter`.

There are no automatic updates in the beta. To remove Presenter, use **Windows Settings › Apps › Installed apps**. Your project stays on the computer; delete that folder yourself if you want it gone too.

## Fixes

- **Presenter closing by itself:** started the normal way, by double-clicking, Presenter closed as soon as it had something to write in its log, such as when you added a song or clicked a slide to show it.
- **Settings going back to their defaults:** the theme, text size and colours were lost each time Presenter closed, and Spanish couldn't be turned on from Settings. They now stay.
- **Restore Defaults:** the Appearance and Text Size lists now show the choices it puts back.

## New since beta 1

- **An installer instead of a zip:** no folder to unzip and keep together.
- **The same icon as the Mac app:** on the shortcuts, the installer and the windows.
- **Settings (File › Settings…, Ctrl+,):** dark, light or the same as Windows; the text size on the operator screen (slides and outputs keep theirs); and the colours for LIVE and each kind of song section, with Restore Defaults. They're kept on that computer, not in the project.
- **Presenter in Spanish:** every window, menu and message. Settings › Language chooses English, Español or the same as Windows, and applies the next time Presenter opens. **Restart Presenter Now** does that straight away.
- **Space after clicking a button:** Space moved to the next slide *and* pressed the button clicked last, which could close the audience output mid-song. Space now only moves on.

## Not in this beta yet

Videos and audio don't play (a slide with a video background shows black behind its words), and there are no Bibles, slide editor, themes, stage display, timers, messages or update checks yet. Pictures in HEIC format don't show. These come in later betas, starting with what testers ask for most.

## Reporting a problem

Use [GitHub Issues](https://github.com/alps2005/PresenterApp/issues) and say what you did and what happened. If something went wrong inside the app, it wrote a file in `%LOCALAPPDATA%\Presenter\Logs` (**Help › Open the Problem Logs Folder**): please attach it.
