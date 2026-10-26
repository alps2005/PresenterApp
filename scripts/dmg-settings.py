# dmgbuild settings for the release DMG (.github/workflows/release.yml): the app, an Applications shortcut and a
# background picture from scripts/make-dmg-background.swift, whose positions these match. APFS with lzfse (ULFO),
# as Sparkle recommends.
#
# Usage: dmgbuild -s scripts/dmg-settings.py -D app=<Presenter.app> -D background=<background.tiff> \
#            Presenter Presenter-v1.2.0.dmg
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)

filesystem = "APFS"
format = "ULFO"

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extension = [os.path.basename(app)]

background = defines["background"]  # noqa: F821
# The height includes the title bar. The picture is taller than what shows, and its text stays clear of the path
# bar, which Finder adds when someone has it turned on everywhere.
window_rect = ((200, 120), (600, 432))
default_view = "icon-view"
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    os.path.basename(app): (160, 145),
    "Applications": (440, 145),
}
