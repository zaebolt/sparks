# Sparks

A menu bar scratchpad for the five things you're actually doing today.

Lives as a lightbulb on the right side of the macOS menu bar.
Click it — or press **⌥Space** — and the panel opens with the cursor already in
the input, ready to type.

## Rules

- **Five open tasks, hard cap.** When five are open the input is disabled. Tick
  one off and a slot frees up.
- **Completed tasks stay visible all day**, struck through under "Done today".
- **...And are gone tomorrow.** At the change of calendar day, completed tasks are
  deleted. Nothing accumulates, there is no history, there is no archive.
- **Unfinished tasks reorder by dragging.** Completed ones stay put.
- **Tasks still open do carry over** — they're still open, so they still count
  against the five.

## Using it

| | |
|---|---|
| `⌥Space` | Open / close the panel |
| `Return` | Add the typed task |
| `Esc` | Close and hand focus back to what you were doing |
| Click a task | Complete it (click again to reopen it) |
| Drag a task | Reorder it among the unfinished ones |
| Right-click mid-drag | Abandon the drag, leaving the order untouched |
| Hover a row, click `✕` | Delete a task outright |
| Right-click the icon | Open at Login, Quit |

## Build and install

```sh
./build.sh                          # produces build/Sparks.app
cp -R build/Sparks.app ~/Applications/
open ~/Applications/Sparks.app
```

Requires the Xcode command line tools. No dependencies, no network access, no
Accessibility permission — the hot key is registered through Carbon, which does
not need one.

To have it start automatically, right-click the menu bar icon and tick
**Open at Login**.

## Where things live

| File | |
|---|---|
| `Sources/Sparks/Store.swift` | Tasks, the five-task cap, the day rollover, persistence |
| `Sources/Sparks/ContentView.swift` | The panel |
| `Sources/Sparks/AppDelegate.swift` | Status item, popover, focus handling |
| `Sources/Sparks/HotKey.swift` | The ⌥Space registration |
| `Sources/Sparks/Icon.swift` | The icon and the accent colour |
| `Tools/makeicon.swift` | Renders the `.icns` at build time |
| `Tests/` | The test suites and their runner |

State is a single JSON blob in `UserDefaults` under `sparks.state.v1` — day
stamp plus tasks. Deleting that key resets the app.

## Tests

```sh
./Tests/run.sh              # all four suites
./Tests/run.sh store        # just the headless one
```

`StoreTests` is headless — the cap, the day rollover, reordering, persistence.
The other three drive the real status item and the real popover with synthetic
events, and assert against what actually ends up on screen:

- `PanelTests` — the panel hangs off the icon, grows with its content, and a
  click completes a task.
- `HoverTests` — a row lights up from every entry point, and the `✕` deletes.
- `ReorderTests` — dragging moves a task one place, several places, and back;
  a short nudge does nothing; a plain click still completes.

The last three briefly take focus and move the pointer, so leave the mouse alone
while they run. They hold focus deliberately — the panel is a transient popover
and closes when the app is not active, which otherwise shows up as an unrelated
failure. They also stand down any running copy of the app first, since it
owns the hot key and a menu bar slot.

## Changing the look

The menu bar glyph is one line in `Icon.swift`:

```swift
static let variant: Variant = .sparkInBulb
```

Other options are `.bulbFilled`, `.bulbOutline`, `.bulbMaxFilled`,
`.bulbMaxOutline` and `.ledBulb`. Rebuild to apply.

The accent is `#8EA0FF`, set in `Palette.accent` in the same file.

## ⌥Space

Two keys, easy to hit one-handed, and unclaimed by macOS out of the box
(`⌃Space` is input sources, `⌘Space` is Spotlight). If another app already owns
it, Sparks logs a note at launch and the menu bar icon keeps working.

## Implementation notes

These are worth reading before changing the row or the panel.

**Reordering commits on drop, not as you drag.** Mutating the list mid-drag
tears down and rebuilds the row the gesture is attached to, which cancels the
gesture; the symptom is that a task will only ever move one place per drag. So
the target index is computed as the pointer moves, the other rows are shifted
visually to open a gap, and `moveOpen` runs once on release. The drag needs 4pt
of travel before it engages, which leaves a plain click free to complete the
task.

**Right-clicking mid-drag is handled by an event monitor, not the gesture.**
SwiftUI treats the right button as an interruption and drops the `DragGesture`
without ever calling `onEnded`, so the row would stay lifted and the gap open
until something else reset it. `watchForCancel` installs a local monitor for the
duration of a drag. Note there is deliberately no "cancelled" flag held until
the button comes up: the gesture is already dead by then, so a flag buys
nothing, and anything that failed to clear it would stop dragging working
altogether. Instead `cancelDrag` sets `dragTo` back to `dragFrom`, so a stray
`onEnded` finds nothing to move.

**The row carries `.contentShape(Rectangle())` so hover covers its whole
rectangle**, padding included. Without it, hover is hit-tested against the row's
content, and only fires when the pointer happens to cross a glyph or a control
on its way in.

**The `✕` is only clickable while the row is hovered.** It uses `.opacity`
rather than `.hidden()`, but SwiftUI still skips hit-testing a fully transparent
view. That is the intended behaviour, not a bug — and it means a synthetic click
cannot reach it without real hover, which is why `HoverTests` covers deletion
rather than `PanelTests`.

**Row controls line up with the task text using the font's own metrics**
(`rowCapCentre` in `ContentView.swift`) rather than a hardcoded line height, so
the checkbox and the `✕` sit centred on the first line of a task however many
lines it wraps to. The outer frame must state an explicit height: without one
the button's hit region collapses to a sliver down its right edge — it still
draws, it just stops being clickable.

**The panel waits for the status item to be placed before showing.** Right after
launch the menu bar may not have given it a slot yet, and anchoring to a window
still sitting at the origin opens the panel in the corner of the screen instead
of under the icon.

## License

MIT — see [LICENSE](LICENSE).
