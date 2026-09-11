// macOS-style ALT+TAB switcher: a horizontal bar of window icons with the
// selected window's title beneath it.
//
// This is the display half only. All key handling and all state live in
// altswitch.lua next to this file, loaded from the Hyprland config. It owns the
// frozen window list and the cursor, and drives this panel over IPC:
//
//   omarchy-shell altswitch show '{"windows":[...],"index":1}'
//   omarchy-shell altswitch select 2
//   omarchy-shell altswitch hide
//
// The panel takes exclusive keyboard focus purely so that keys the switcher
// does not bind are swallowed instead of leaking into the window underneath.
// It deliberately handles no keys of its own, so there is exactly one place
// where a keypress can be interpreted.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  // Injected by Omarchy's panel loader.
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var windows: []
  property int selectedIndex: 0

  readonly property string pluginId: String((manifest && manifest.id) || "putueddy.altswitch")
  readonly property var pluginEntry: {
    const config = shell ? shell.shellConfig : null
    const plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (let i = 0; i < plugins.length; i++) {
      const entry = plugins[i]
      if (entry && entry.id === root.pluginId) return entry
    }
    return ({})
  }
  // Optional user-defined icon overrides. Windows whose class has no desktop
  // entry (or the wrong icon) can be mapped to a specific icon here, from the
  // plugin entry in shell.json:
  //
  //   "iconOverrides": [
  //     { "appClass": "org.quickshell", "title": "Radio Atlas",
  //       "icon": "~/.config/quickshell/radio-atlas/radio.svg" }
  //   ]
  //
  // `appClass` is required and matched exactly. `title` is optional; when it is
  // present the window title must match it exactly too. `icon` may be an icon
  // name from the active theme, an absolute path, a ~/ path, or a file:// URL.
  readonly property var iconOverrides: Array.isArray(pluginEntry.iconOverrides) ? pluginEntry.iconOverrides : []

  readonly property var selectedWindow: root.windows.length > 0
    ? root.windows[Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))]
    : null
  readonly property string selectedTitle: {
    if (!root.selectedWindow) return ""
    const title = String(root.selectedWindow.title || "").trim()
    return title.length > 0 ? title : root.friendlyAppName(root.selectedWindow.appClass)
  }

  // macOS-style icon bar geometry (mirrors the Caelestia AltSwitch rework).
  readonly property int iconSize: Style.space(48)
  readonly property int cellSize: Style.space(64)
  readonly property int cellGap: Style.space(6)
  readonly property int cellRadius: Style.space(16)
  readonly property int barPadding: Style.space(12)
  readonly property int barHeight: cellSize + barPadding * 2
  readonly property int barRadius: Style.space(22)
  readonly property int titleGap: Style.space(16)
  readonly property int maxBarWidth: Math.max(cellSize, panel.width - Style.space(48))
  readonly property int desiredBarWidth: root.windows.length > 0
    ? root.windows.length * cellSize + (root.windows.length - 1) * cellGap + barPadding * 2
    : 0
  readonly property int barWidth: Math.min(desiredBarWidth, maxBarWidth)

  function updatePluginSetting(name, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false

    const next = ({})
    for (const key in root.pluginEntry) if (key !== "id") next[key] = root.pluginEntry[key]
    next[name] = value
    shell.updateEntryInline(root.pluginId, next)
    return true
  }

  function setPluginSetting(name, rawValue) {
    if (name !== "iconOverrides") return "unknown setting: " + name

    let parsed
    try {
      parsed = JSON.parse(String(rawValue || "[]"))
    } catch (error) {
      return "iconOverrides must be a JSON array"
    }
    if (!Array.isArray(parsed)) return "iconOverrides must be a JSON array"
    if (!root.updatePluginSetting(name, parsed)) return "unavailable"
    return "ok"
  }

  function friendlyAppName(appClass) {
    const raw = String(appClass || "").trim()
    if (!raw) return "Unknown"

    // Window classes usually match a desktop-file id or StartupWMClass.
    // Let Quickshell resolve both before falling back to formatting the id.
    const entry = DesktopEntries.heuristicLookup(raw)
    if (entry && entry.name) return String(entry.name)

    let name = raw.replace(/^steam_app_/i, "")
    if (name.indexOf(".") !== -1) name = name.split(".").pop()
    name = name.replace(/[_-]+/g, " ").trim()
    return name.replace(/(^|\s)\S/g, function(letter) { return letter.toUpperCase() })
  }

  // Turn an override icon value into a QML image source. Theme icon names go
  // through Quickshell.iconPath; paths and file:// URLs are used directly.
  function resolveIconSource(icon) {
    const value = String(icon || "").trim()
    if (!value) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0 || value.indexOf("qrc:/") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    if (value.indexOf("~/") === 0) return Util.fileUrl((Quickshell.env("HOME") || "") + value.slice(1))
    return Quickshell.iconPath(value, true)
  }

  function overrideIcon(win) {
    const appClass = String(win && win.appClass || "").trim()
    const title = String(win && win.title || "").trim()
    for (let i = 0; i < root.iconOverrides.length; i++) {
      const override = root.iconOverrides[i]
      if (!override || typeof override !== "object") continue
      if (String(override.appClass || "").trim() !== appClass) continue
      if (override.title !== undefined && String(override.title).trim() !== title) continue
      const resolved = root.resolveIconSource(override.icon)
      if (resolved) return resolved
    }
    return ""
  }

  function appIcon(win) {
    const override = root.overrideIcon(win)
    if (override) return override

    const raw = String(win && win.appClass || "").trim()
    const entry = raw ? DesktopEntries.heuristicLookup(raw) : null
    const icon = entry ? String(entry.icon || "") : ""

    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return Util.fileUrl(icon)
    return Quickshell.iconPath(icon || "application-x-executable", true)
  }

  function show(payloadJson) {
    // Armed before anything that can throw, so a payload this panel cannot read
    // can never strand it on screen.
    watchdog.restart()

    let payload
    try {
      payload = JSON.parse(payloadJson)
    } catch (error) {
      console.warn("altswitch: unreadable payload:", error)
      root.hide()
      return
    }

    root.windows = payload.windows || []
    root.selectedIndex = payload.index || 0
    root.opened = root.windows.length > 0
  }

  function select(index) {
    root.selectedIndex = index
    watchdog.restart()
  }

  function hide() {
    watchdog.stop()
    root.opened = false
  }

  // A switch ends when ALT is released, which is a keybind in the Hyprland
  // config. If that release is ever missed the panel would sit on screen for
  // good, so it also gives up on its own and tells the config to reset.
  Timer {
    id: watchdog
    interval: 10000
    onTriggered: {
      root.hide()
      Quickshell.execDetached(["hyprctl", "eval", "__altswitch_cancel()"])
    }
  }

  IpcHandler {
    target: "altswitch"

    function show(payloadJson: string): string {
      root.show(payloadJson)
      return "ok"
    }

    function select(index: int): string {
      root.select(index)
      return "ok"
    }

    function hide(): string {
      root.hide()
      return "ok"
    }

    function state(): string {
      return root.opened ? "open" : "closed"
    }

    function set(name: string, value: string): string {
      return root.setPluginSetting(name, value)
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-altswitch"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never grab the keyboard. A grab here can outlive the switch and leave the
    // desktop with no way to dismiss it; a purely visual surface cannot.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // macOS-style icon bar: one cell per window, the selected one highlighted.
    Rectangle {
      id: bar

      width: root.barWidth
      height: root.barHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      radius: root.barRadius
      color: Color.menu.background

      ListView {
        id: list

        anchors.fill: parent
        anchors.margins: root.barPadding
        orientation: ListView.Horizontal
        spacing: root.cellGap
        clip: true
        interactive: false
        model: root.windows
        currentIndex: root.selectedIndex
        highlightMoveDuration: 0
        // Keep the cursor on screen when there are more windows than fit.
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        highlightRangeMode: ListView.ApplyRange

        delegate: Item {
          required property int index
          required property var modelData

          width: root.cellSize
          height: root.cellSize

          Rectangle {
            anchors.fill: parent
            radius: root.cellRadius
            color: index === root.selectedIndex ? Util.alpha(Color.foreground, 0.18) : "transparent"
          }

          Image {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            source: root.appIcon(modelData)
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * Screen.devicePixelRatio
            sourceSize.height: height * Screen.devicePixelRatio
            asynchronous: true
            smooth: true
          }
        }
      }
    }

    // Selected window's title, centred under the bar.
    Text {
      id: titleLabel

      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round((parent.height + root.barHeight) / 2) + root.titleGap
      width: Math.min(implicitWidth, parent.width - Style.space(48))
      visible: root.selectedTitle.length > 0
      text: root.selectedTitle
      color: Util.alpha(Color.menu.text, 0.9)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.title
    }
  }
}
