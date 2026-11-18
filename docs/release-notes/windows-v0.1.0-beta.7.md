The seventh beta of **Presenter for Windows** brings **Scripture**: Bible passages on slides, as on the Mac.

This is still an early beta. Please try it at a rehearsal before using it in a service, and [tell us](https://github.com/alps2005/PresenterApp/issues) what goes wrong or what you miss.

## Install

1. Download **Presenter-Windows-0.1.0-beta.7-Setup.exe** below.
2. The app isn't code-signed yet, so Microsoft Edge may say the file **"isn't commonly downloaded"** and hold on to it. In Edge's Downloads list, point at the file, click **…** (More actions) and then **Keep**. Edge then asks you to make sure you trust the file: click the arrow next to **Delete** and choose **Keep anyway**.
3. Double-click the file. If Windows says **"Windows protected your PC"**, click **More info**, then **Run anyway**.
4. Presenter installs for the person signed in, adds itself to the Start menu and the Desktop, and opens.

Needs Windows 10 or 11 (64-bit). Nothing else to install: the app carries what it needs.

If Defender or your browser still blocks the download, please [tell us](https://github.com/alps2005/PresenterApp/issues) rather than turning Defender off.

**Coming from beta 2 to 6?** Close Presenter and run the installer. It says Presenter is already installed: click **Update**.

**Coming from beta 1?** Close it and run the installer. You can then delete the old unzipped folder.

Your project carries over either way, because it's kept separately in `%LOCALAPPDATA%\Presenter`.

There are no automatic updates in the beta. To remove Presenter, use **Windows Settings › Apps › Installed apps**. Your project stays on the computer; delete that folder yourself if you want it gone too.

## New: Scripture (Show › Scripture…, Ctrl+B)

- **Import a Bible:** Presenter reads Zefania, OSIS, USFX and USX files, the free formats public-domain and open translations are shared in, such as the Reina-Valera 1909, the King James Version or the World English Bible. Presenter doesn't download or include any. For a USX Bible, choose all its book files at once. Bibles are kept on the computer in `%LOCALAPPDATA%\Presenter\Bibles`, not in the project.
- **Type a reference** such as *Juan 3:16-18*, *1 Co 13:4-7* or *John 3:16*, in Spanish or English, and check the verses before adding them. A verse the Bible doesn't have is pointed out.
- **Or search for words** and choose a verse from the list.
- **Add to Show:** the passage becomes slides at the end of the show, with the verses per slide (1 to 4), verse numbers and the reference as you choose, in a theme (one named *Scripture* is picked first). A **second Bible** shows the same verses in another translation below, for bilingual services.
- **Rename** a Bible or change the abbreviation shown on slides, or **Remove** it. Slides already made from it stay.

## Fixed in betas 5 and 6

- **Screen readers:** the colour buttons, the lists in Settings and the main window, and the scroll bar buttons now say what they are.

## Not in this beta yet

Videos and audio don't play (a slide with a video background shows black behind its words), and there's no slide editor, themes to edit, stage display, timers, messages or update checks yet. Pictures in HEIC format don't show. Scripture over the cued slide (the Mac's Live panel › Scripture…) isn't here yet either. These come in later betas.

## Reporting a problem

Use [GitHub Issues](https://github.com/alps2005/PresenterApp/issues) and say what you did and what happened. If something went wrong inside the app, it wrote a file in `%LOCALAPPDATA%\Presenter\Logs` (**Help › Open the Problem Logs Folder**): please attach it.
