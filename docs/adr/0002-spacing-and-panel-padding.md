# ADR 0002: Spacing, panel padding and rows that fit

- **Status:** Accepted
- **Date:** 2026-10-17
- **Related:** [ADR 0001](0001-quiet-native-design.md)

## Context

On a 2019 iMac running beta 4, the slide editor's inspector had no margins. Its 16 pt padding was there, but the
image and video background rows held controls that couldn't shrink:
- a segmented Scaling picker with `.fixedSize()` that still drew its "Scaling" label;
- a 100 pt Dim slider, or the Loop and Mute toggles.

Together they came to about 300 pt, in a column with 278 pt of room. A `VStack` is as wide as its widest row, so
the whole inspector grew past its column and the clipping took the padding with it, on every row.

Development happens on macOS 27, where the inspector floats as an inset pane and the overflow didn't show. On
macOS 14 and 15 the inspector sits flush with the window edge, and controls are measured slightly differently.

An audit also found:
- panels padding 10, 16 or 20 pt with no rule;
- column widths and control widths written as literals in each view;
- a 0.5 pt hairline that blurs to a faint grey on 1x displays.

## Decision

- **One padding rule** (documented on `Spacing` in `Presenter/DesignSystem/Tokens.swift`):

  | Surface | Padding |
  |---|---|
  | Side panels, bottom panels (Quick Edit, Media) and inspectors | `Spacing.lg` (16) |
  | Sheets | `Spacing.xl` (20) |
  | Popovers (`PopoverForm`) | `Spacing.lg` (16) |
  | Rows and cards (`RowCard`) | `Spacing.md` (10) |

- **Column widths are tokens.** `Widths` holds the operator sidebar, the live panel, and the editor's thumbnails
  and inspector, plus the control widths that recur (font menu, number field, value label, compact slider).
- **Every inspector row must fit `Widths.inspectorContentWidth`** (238 pt, the inspector's narrowest width less
  its padding). A row that can't shrink (segmented pickers, `.fixedSize()`, fixed-width sliders) needs a fallback:
  - wrap it in `ViewThatFits(in: .horizontal)` with a stacked or menu version second; or
  - give its stretchy part a minimum width instead of a fixed one.

  Segmented pickers in a narrow column hide their label (`.labelsHidden()`) and keep an `accessibilityLabel`.
- **Text editors inset their text** by `Spacing.sm` inside their raised background.
- **Hairlines are one pixel** (`hairlineBorder`), not 0.5 pt.

## Consequences

- **Good:** the inspector keeps its margins at any width it allows, on every macOS version Presenter supports,
  and new panels have a rule to follow.
- **Cost:** Quick Edit and the media bin grow by a few points, and `ViewThatFits` builds a row's controls twice.
- **Checking it:** in a Debug build, `overflowGuard` outlines in amber any panel whose content is wider than its
  column, and `scripts/layout-screenshots.sh` captures each inspector tab at its narrowest width.
