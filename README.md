# Pomodoro

A pomodoro timer for the Omarchy bar, built like a little toaster. Twist the
kitchen-timer dial to set how long to focus, push the lever down to start, and
it pops back up when the time is done.

While a focus session runs, **you're locked to the workspace you started it
on.** Switching to another workspace, opening the scratchpad, or jumping to
another monitor bounces you straight back.

![Panel](preview.png)

## Install

```bash
omarchy plugin add https://github.com/21J3phy/omarchy-pomodoro --enable
```

Requires `python3` (already on Omarchy) and Hyprland 0.56 or newer, which has
the Lua dispatchers.

## Use

- **Click** the timer in the bar to open the toaster.
- **Twist the dial** (drag it clockwise, or scroll) to set the focus length,
  from 1 to 60 minutes.
- **Push the lever down** to start.
- **BREAK / SKIP / STOP** do what they say.
- **Right-click** the bar icon to start a session straight away.
- **Middle-click** the bar icon, or press **Float** in the panel, to toggle the
  floating timer.

### Floating timer

A small readout that stays on top of every window, fullscreen ones included,
on whichever monitor you turned it on from. It never takes keyboard focus.

- **Drag** it anywhere; it remembers the spot.
- **Click** it to open the toaster.
- **×** or a middle-click hides it. ▶ starts focus when idle; the expand
  button opens the toaster while a session runs.

From a keybinding: `omarchy-shell 21j3phy.pomodoro.state mini` toggles it on
the focused monitor (`showMini` / `hideMini` also exist).

### Bailing out costs you a sentence

Ending a focus session early, whether with STOP, the lever, BREAK or SKIP,
opens a box you have to type this into, word for word:

> I am being very unproductive and wasting my time by doing this.

Pasting doesn't work. The script checks the sentence itself, so the terminal
won't get you out either. Breaks have no such toll.

In the bar, a running timer is a small dial whose wedge is the time left. It's
red while you focus and green on a break, with the minutes beside it.

When focus ends you get a chime, the break starts on its own, and the
workspace unlocks. When the break ends, the notification has a **Start focus**
button. The row of pips counts sessions toward the next long break.

### Settings

Under **Settings** in the panel:

- break lengths and how often the long break comes
- **Lock to workspace**: on by default
- **Strict mode**: the lever locks and BREAK/SKIP/STOP stop working until the
  timer ends
- **Start breaks automatically**

## CLI

The panel drives `bin/pomodoro`, which you can also use directly:

```
bin/pomodoro start [minutes]    # focus, locked to the current workspace
bin/pomodoro break [minutes]
bin/pomodoro skip | stop | status
bin/pomodoro stop --phrase "I am being very unproductive and wasting my time by doing this."
bin/pomodoro stop --force --phrase "..."   # escape hatch for strict mode
bin/pomodoro set short 10       # focus, short, long, longEvery, lock, strict, autoBreak
bin/pomodoro set miniX 40 miniY 40   # several pairs at once; true/false keys take "toggle"
bin/pomodoro mini [on|off|toggle]    # the floating timer
```

During focus, `stop`, `skip` and `break` need `--phrase`. During a break
they don't.

To open the STOP confession from a keybinding:
`omarchy-shell 21j3phy.pomodoro.state stop`.

Settings live in `~/.config/omarchy/pomodoro.json`, daily stats in
`~/.local/state/omarchy-pomodoro/stats.json`, and the running session in
`$XDG_RUNTIME_DIR/omarchy-pomodoro/`.

## How the lock works

`pomodoro start` starts a small daemon that reads Hyprland's event socket
(`.socket2.sock`). When a `workspacev2`, `focusedmonv2` or `activespecialv2`
event leaves the locked workspace, it dispatches
`hl.dsp.focus({ workspace = "<id>" })` or closes the special workspace. It also
checks the active workspace every two seconds in case it missed an event. The
daemon exits when no session is running.

## License

MIT
