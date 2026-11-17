The sixth beta of **Presenter for Windows**. More fixes for people who use a screen reader; everything else is as in beta 5.

This is still an early beta. Please try it at a rehearsal before using it in a service, and [tell us](https://github.com/alps2005/PresenterApp/issues) what goes wrong or what you miss.

## Install

1. Download **Presenter-Windows-0.1.0-beta.6-Setup.exe** below.
2. The app isn't code-signed yet, so Microsoft Edge may say the file **"isn't commonly downloaded"** and hold on to it. In Edge's Downloads list, point at the file, click **…** (More actions) and then **Keep**. Edge then asks you to make sure you trust the file: click the arrow next to **Delete** and choose **Keep anyway**.
3. Double-click the file. If Windows says **"Windows protected your PC"**, click **More info**, then **Run anyway**.
4. Presenter installs for the person signed in, adds itself to the Start menu and the Desktop, and opens.

Needs Windows 10 or 11 (64-bit). Nothing else to install: the app carries what it needs.

If Defender or your browser still blocks the download, please [tell us](https://github.com/alps2005/PresenterApp/issues) rather than turning Defender off.

**Coming from beta 2, 3, 4 or 5?** Close Presenter and run the installer. It says Presenter is already installed: click **Update**.

**Coming from beta 1?** Close it and run the installer. You can then delete the old unzipped folder.

Your project carries over either way, because it's kept separately in `%LOCALAPPDATA%\Presenter`.

There are no automatic updates in the beta. To remove Presenter, use **Windows Settings › Apps › Installed apps**. Your project stays on the computer; delete that folder yourself if you want it gone too.

## Fixed since beta 5

- **Lists with a screen reader:** Narrator and other screen readers now say what each list is for: Appearance, Text size and Language in Settings, and Show and Audience output screen in the main window. Before, they read nothing.
- **Scroll bars with a screen reader:** the arrow buttons read "Avalonia.Controls.PathIcon". They now say Scroll up, Scroll down, Page up and so on, in Spanish too.

## Fixed in beta 5

- **Colours in Settings with a screen reader:** each colour button says which colour it is, such as "Verse colour" or, in Spanish, "Color de Verso", instead of "Avalonia.Controls.Panel".

Betas 1 to 4 brought the installer, the icon, Settings, Spanish and the fixes listed in the [beta 4 notes](https://github.com/alps2005/PresenterApp/releases/tag/windows-v0.1.0-beta.4).

## Not in this beta yet

Videos and audio don't play (a slide with a video background shows black behind its words), and there are no Bibles, slide editor, themes, stage display, timers, messages or update checks yet. Pictures in HEIC format don't show. These come in later betas, starting with what testers ask for most.

## Reporting a problem

Use [GitHub Issues](https://github.com/alps2005/PresenterApp/issues) and say what you did and what happened. If something went wrong inside the app, it wrote a file in `%LOCALAPPDATA%\Presenter\Logs` (**Help › Open the Problem Logs Folder**): please attach it.
