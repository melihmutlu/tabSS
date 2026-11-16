# tabSS

A small, fast replacement for the macOS Cmd+Tab switcher that switches between **windows**, not apps.

- Every window on every Space and display, including minimized windows and windows of hidden apps
- Window thumbnails, most recently used first
- Native look: system material, light and dark mode, Reduce Transparency
- Runs in the background from login, with no polling while idle

## Use

| Keys | Action |
|---|---|
| Cmd+Tab (tap) | Back to the previous window |
| Cmd+Tab (hold) | Show the switcher |
| Tab / Shift+Tab, → / ← | Next / previous |
| ↓ / ↑ | Next / previous row |
| Release Cmd, Return | Switch to the selected window |
| Esc | Cancel |
| Mouse | Hover to select, click to switch |

Running apps without windows appear after all windows; choosing one reopens it, like a Dock click.

## Build and install

Requires Xcode (Swift 6) on macOS 14 or later. No other dependencies.

```sh
make cert      # once: local code-signing identity, so permission grants survive rebuilds
make install   # build, sign, copy to ~/Applications and launch
```

Signing asks the Keychain for approval each time; choose **Allow**, not "Always Allow".

On first launch, grant **Accessibility** (required) and **Screen Recording** (optional; without it tiles show app icons instead of thumbnails). Both are in System Settings › Privacy & Security. If the menu bar icon still offers "Grant Accessibility…" after granting it, remove tabSS from the list, add it again and relaunch: an old entry from a differently signed build doesn't count.

Other targets: `make test` (unit tests), `make smoke` (checks the installed app stays alive with near-zero idle CPU), `make uninstall`.

## Notes

- Launch at Login is on after the first run; toggle it from the menu bar icon. Turn it off there before `make uninstall`, or remove tabSS later in System Settings › General › Login Items.
- While a password field has focus, macOS hides keystrokes from all apps, so Cmd+Tab falls back to the system switcher there.
- Finding windows on other Spaces and focusing them across Spaces uses a few undocumented macOS functions (the same ones AltTab uses), isolated in `Sources/tabSS/Windows/PrivateAPI.swift`. If a future macOS removes one, that feature falls back to public APIs.
- Thumbnails are taken when tabSS starts and whenever you leave a window. macOS's public capture API can't see windows on other Spaces or minimized ones, so those show their app icon until you've visited them once, then keep their last picture.
- Thumbnails stay in memory only. The switcher panel asks to be left out of screen sharing and recordings, but recent macOS versions don't always honor that, so avoid opening it while sharing your whole screen.

## Future work

- Cmd+Q / Cmd+W while the switcher is open, to quit the selected app or close the selected window: a key binding, a `SwitcherCommand` case, and its effect in the state machine and `Switcher`.
- Cmd+\` to switch between the current app's windows only, like the native shortcut.
- Type to filter the panel by app name or window title.
- An "icons only" option for screen sharing, since macOS doesn't reliably keep the panel out of recordings.
- Above 128 windows, drop the least recently used thumbnails instead of the oldest captured.

## Disclaimer

<sub><sup>This code has been vibecoded and not reviewed by any human. Use at your own risk.</sup></sub>
