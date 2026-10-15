# ADR 0001: Quiet native design, not Liquid Glass

- **Status:** Accepted
- **Date:** 2026-10-15
- **Revisit:** when building with the macOS 28 SDK

## Context

Building Presenter with the macOS 26 and later SDKs gives it Liquid Glass automatically. Presenter never asks
for glass (it uses no `glassEffect` or glass button styles), but it gets it implicitly in about 30 places:
- window toolbars and their grouped buttons;
- the floating `NavigationSplitView` sidebar and its search field;
- blurred scroll edges on the slide workspace, the live panel and the editor canvas;
- segmented pickers, popovers, menus and sheets.

The app also used `.regularMaterial` (the thumbnail-size slider over the slide grid) and `.bar` (the Take Live
bar).

Presenter's operator console runs during services in dark booths, where the operator glances at it between
cues. An audit found:
- **Translucency hurts glanceability:** moving slides show through the panels over them.
- **The critical states were hard to tell apart:**
  - BLACKOUT was a black badge on a dark panel.
  - NOTHING LIVE, CLEARED and BACKGROUND ONLY were identical grey badges.
  - LIVE and CUED badges were about 10 pt.
  - CUED used the system accent colour, so with a red or grey accent it could look like LIVE or like nothing.
- **There's no full opt-out:** Apple's `UIDesignRequiresCompatibility` key is ignored for apps built with the
  Xcode 27 SDKs.

The stage display (solid black, large type) was the part of the app that already worked well in a booth.

## Options considered

1. **Embrace Liquid Glass.** Use glass button styles and glass effects throughout, the way Apple's apps do.
   It looks current, but it makes the glanceability problem worse, and an operator console isn't a
   content-browsing app.
2. **Opt out entirely.** That isn't possible with current SDKs. The compatibility key is ignored, and the
   system still draws popovers, menus and sheets.
3. **Quiet native (chosen).** Keep Apple's toolbar, sidebar, controls, popovers and sheets, but turn glass
   down wherever Presenter controls it, and give show states one fixed look each.

## Decision

Quiet native:
- **Solid show surfaces.** The workspace, live panel, Take Live bar, sidebars and editor canvas are opaque
  (`solidPanel`, `solidSidebar`). The window toolbar is solid (`solidToolbar`, macOS 15+). Scroll edges are hard
  instead of blurred (`hardScrollEdges`, macOS 26+). All of these are in `Presenter/DesignSystem/QuietChrome.swift`
  and do nothing on systems without the API.
- **Dark by default.** The operator window is dark unless View › Follow System Appearance is on.
- **Fixed state colours.** In `Presenter/DesignSystem/Tokens.swift`:
  - LIVE is red, CUED is blue and warnings are amber.
  - EDITED is purple, so orange no longer means two things.
  - None of them follows the system accent colour. The AccentColor asset is the same blue.
- **State never shown by colour alone.** `StateBadge` always shows an icon and a word, in a larger caption
  bold font. Each state also has its own shape:
  - BLACKOUT is black with a red outline;
  - BACKGROUND ONLY is outlined in red;
  - CLEARED is filled grey;
  - NOTHING LIVE is a dashed, hairline outline.
- **One tile frame:** `tileFrame` outlines a live tile in red and a cued tile in blue everywhere: the slide grid,
  the live panel's Audience, Up Next and Cued, the media bin, props, and the editor's thumbnails.
- **Popovers, menus and sheets stay as the system draws them.** Glass can't be removed there, and they're brief.
- **No shared glass capsule in the operator toolbar.** On macOS 26+, Quick Edit, Media and Output each use
  `sharedBackgroundVisibility(.hidden)`. Compared side by side on screen, the buttons no longer sit in translucent
  grey capsules, and an active toggle (a solid blue pill on its own) is easier to tell from an inactive one
  (a plain icon). Older systems keep the grouped buttons.

## Consequences

- **Good:** the console reads at a glance, states are distinguishable without colour, and the look no longer
  depends on the user's accent colour.
- **Cost:**
  - Presenter looks a little less like Apple's own macOS 26+ apps.
  - The `#available` guards add some code, which can go once the deployment target reaches macOS 26.
- **Revisit at the macOS 28 SDK:**
  - Has Apple added a real opt-out, or changed what glass does to toolbars and sidebars?
  - Can the deployment target move to macOS 26 so the guards can go?
