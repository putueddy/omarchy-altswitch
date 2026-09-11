# Changelog

## 1.1.0 — 2026-09-11

Fork additions, based on upstream 1.0.0 (commit `8f54d68`, 2026-08-30).
Nothing from upstream is removed; the new appearance is opt-in.

### Added

- **`style` setting** — `"list"` (default) keeps the original list card;
  `"bar"` switches to a macOS-style horizontal bar of window icons with the
  selected window's title drawn centred beneath it. The selected cell is
  highlighted, and the bar scrolls to keep the cursor visible when there are
  more windows than fit.

  ```json
  { "id": "putueddy.altswitch", "style": "bar" }
  ```

  ```sh
  omarchy-shell altswitch set style bar
  ```

- **`iconOverrides` setting** — map a window to a specific icon when its class
  has no desktop entry or resolves to the wrong one. Each entry matches by
  `appClass` and, optionally, by exact `title`.

  ```json
  {
    "id": "putueddy.altswitch",
    "style": "bar",
    "iconOverrides": [
      {
        "appClass": "org.quickshell",
        "title": "Radio Atlas",
        "icon": "~/.config/quickshell/radio-atlas/radio.svg"
      }
    ]
  }
  ```

  `icon` accepts a theme icon name, an absolute path, a `~/` path, or a
  `file://` URL. It can also be set over IPC:

  ```sh
  omarchy-shell altswitch set iconOverrides '[{"appClass":"org.quickshell","title":"Radio Atlas","icon":"~/.config/quickshell/radio-atlas/radio.svg"}]'
  ```

### Changed

- Icons without an override still resolve exactly as before, through the window
  class and the desktop entries.

### Unchanged

- `altswitch.lua` (state machine, key handling, IPC) is untouched.
- `showIcons` still works, and only affects the `list` style.

### Upgrade notes

- This fork uses the plugin id `putueddy.altswitch`. Do not enable it at the
  same time as `io.github.pablo-merino.altswitch`: both register the `altswitch`
  IPC target, and the second one to load is ignored.
- The default appearance is the original list card. Set `"style": "bar"` to get
  the new icon bar.
