# Changelog

## 1.1.0 — 2026-09-11

Fork additions, based on upstream 1.0.0 (commit `8f54d68`, 2026-08-30).

### Changed

- **New appearance:** the list card (workspace number · icon · app name ·
  window title) is replaced by a macOS-style horizontal bar of window icons.
  The selected window's title is drawn centred beneath the bar. Cells are
  rounded, the selected cell is highlighted, and the bar scrolls to keep the
  cursor visible when there are more windows than fit.
- Window icons are no longer shown alongside their app name in rows; the bar
  is icon-only. `showIcons` is therefore removed (it had no effect on an
  icon-only bar).

### Added

- `iconOverrides` plugin setting: map a window to a specific icon when its
  class has no desktop entry or resolves to the wrong one. Each entry matches
  by `appClass` and, optionally, by exact `title`. Set it in `shell.json`:

  ```json
  {
    "id": "putueddy.altswitch",
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

### Upgrade notes

- This fork uses the plugin id `putueddy.altswitch`. Do not enable it at the
  same time as `io.github.pablo-merino.altswitch`: both register the `altswitch`
  IPC target, and the second one to load is ignored.
- The `showIcons` setting from 1.0.0 no longer exists.
