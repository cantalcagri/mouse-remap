# Mouse Button Remapper

A single-file Swift tool that gives extra mouse buttons the actions I use, as a
lightweight stand-in for Mac Mouse Fix. No UI, no installer: one source file,
one binary.

| Button   | Click        | Hold            | Double click | Double click + hold | Click and drag            |
|----------|--------------|-----------------|--------------|---------------------|---------------------------|
| Middle   | middle click | Mission Control | Shift+Return | Look Up             | Spaces / Mission Control  |
| Button 4 | Back         | Cmd+V           |              |                     |                           |
| Button 5 | Forward      | Cmd+C           |              |                     |                           |

Edit the `bindings` table at the top of `remap.swift` to change any of this.

## Build and run (macOS, Apple Silicon or Intel)

```sh
xcode-select --install          # once, if swiftc is missing
swiftc -O remap.swift -o remap
./remap                         # first run asks for Accessibility for Terminal; grant it, run again
```

Stop with Ctrl+C or `pkill -f "/remap$"`. To start at login, add the `remap`
binary under System Settings > General > Login Items.

`./remap --learn` prints the number of each button you press, if your mouse
reports buttons differently.

## Notes

- Needs Accessibility permission (it intercepts mouse buttons system-wide).
- Quit Mac Mouse Fix or similar tools first; two remappers fight over the same buttons.
- The Spaces drag sends the same undocumented "dock swipe" events a trackpad
  three-finger swipe produces. This works on macOS 26 and earlier. macOS 27
  changed the mechanism, so that one gesture will need updating there.
- Tunables near the top of the file: `holdDelay`, `doubleClickWindow`,
  `dragThreshold`, `originOffsetPerSpace`.

## Credits

Written from scratch with public Apple APIs, except the dock-swipe event
construction in `DockSwipe`, which is ported from Noah Nuebling's
[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix)
(`TouchSimulator.m`), licensed under the MMF License. That license asks that
derived work make its origin apparent, which this note does.
