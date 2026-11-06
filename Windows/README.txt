Presenter for Windows (beta)
============================

A free, open-source presentation app for church services and live events. This is an early beta: please try it
before using it in a service, and tell us what goes wrong.

Starting it
-----------
1. Unzip the whole download into a folder of its own (for example Documents\Presenter). Keep every file together.
2. Double-click Presenter.exe.
3. Windows may say "Windows protected your PC", because the app isn't signed yet. Click "More info", then
   "Run anyway". It only asks the first time.

If it says a file is missing, install the Microsoft Visual C++ Redistributable (x64) from Microsoft's website.

What it does
------------
- Make songs by typing or pasting the words (Show > New Song, Ctrl+N), or import song files: OpenLyrics,
  ProPresenter 7 (.pro), ChordPro, SongSelect (.txt, .usr) and plain text (Show > Import Songs, Ctrl+I).
- Build the order of service, and keep several services ("shows").
- Run it live: click a slide, or use the arrow keys and Space. F1 clears everything, F2 the words, F3 the
  background, F4 blacks out the screen and F5 brings it back. V, C, B and the other section keys jump to a song's
  verse, chorus, bridge and so on.
- The audience output opens full screen on a second display (or projector). With one screen, it opens in a window
  so you can try things out (F11 shows or hides it).
- Open a project exported from Presenter on a Mac (File > Open Project File), with its pictures, and export yours
  to take to another computer.
- Settings (File > Settings, Ctrl+,): dark or light, text size, English or Spanish (Español), and the colours for
  LIVE and each kind of song section.

Not in this beta yet: playing videos and audio, Bibles, editing slide styles, themes, stage display, timers and
messages. Slides made on a Mac with those still show their words and pictures.

Your project
------------
Everything is saved as you go, in %LOCALAPPDATA%\Presenter (File > Open the Project Folder). Each time the app
opens, it keeps a backup there, in Backups.

Problems and ideas
------------------
https://github.com/alps2005/PresenterApp/issues
If the app runs into trouble, it writes what happened in %LOCALAPPDATA%\Presenter\Logs (Help > Open the Problem
Logs Folder). Attach that file to your report.

Presenter is free software under the GNU General Public License, version 3 (see LICENSE.txt).
