pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Every window on this bar's active workspace, as clickable pills. Clicking a
// pill focuses that window and, on a scrolling-layout workspace, centers its
// column in the viewport.
BarWidget {
  id: root
  moduleName: "rahulcodepython.workspace-taskbar"

  // The bar surface belongs to one screen; show that screen's workspace rather
  // than the globally focused one, so each monitor's bar stays truthful.
  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property var workspace: root.monitor ? root.monitor.activeWorkspace : null
  readonly property int workspaceId: root.workspace ? root.workspace.id : -1

  readonly property bool includeFloating: setting("includeFloating", false) === true
  readonly property int maxLabelWidth: Number(setting("maxWidth", 140))

  // Toplevels are read from Hyprland's global list and filtered by workspace.
  // Reading each of these properties inside the binding makes the model react
  // to window creation, movement, title/app-id changes, and focus changes.
  readonly property var windows: {
    var out = []
    var list = Hyprland.toplevels.values
    var wanted = root.workspaceId
    if (wanted <= 0) return out

    for (var i = 0; i < list.length; i++) {
      var toplevel = list[i]
      var ws = toplevel.workspace
      if (!ws || ws.id !== wanted) continue

      var wayland = toplevel.wayland
      // Transient children (file pickers, popovers) belong to their parent,
      // not to the taskbar as separate applications.
      if (!wayland || wayland.parent) continue

      var ipc = toplevel.lastIpcObject || {}
      if (ipc.floating && !root.includeFloating) continue

      // hyprctl reports each window's layout position as `at: [x, y]`. That is
      // what the scrolling tape orders columns by; the toplevel list itself is
      // in creation/stacking order.
      var at = ipc.at
      var x = Number(at && at.length > 1 ? at[0] : (ipc.x || 0)) || 0
      var y = Number(at && at.length > 1 ? at[1] : (ipc.y || 0)) || 0

      out.push({
        address: String(toplevel.address || ipc.address || ""),
        appId: String(wayland.appId || ipc.class || ipc.initialClass || ""),
        title: String(wayland.title || ipc.title || ""),
        floating: ipc.floating === true,
        activated: toplevel.activated === true,
        x: x,
        y: y
      })
    }

    // Match the pills to the actual left-to-right column order on the tape.
    // Windows sharing a column keep a stable top-to-bottom order.
    out.sort(function(a, b) {
      return a.x === b.x ? a.y - b.y : a.x - b.x
    })

    return out
  }

  // A human-readable app name: the desktop entry's name when there is one,
  // otherwise a cleaned-up app id ("com.mitchellh.ghostty" -> "Ghostty").
  function labelFor(win) {
    var appId = win && win.appId ? String(win.appId) : ""
    if (appId) {
      var entry = DesktopEntries.heuristicLookup(appId)
      if (entry && entry.name) return String(entry.name)
    }

    var name = appId || "App"
    var parts = name.split(".")
    if (parts.length > 1) {
      var last = parts[parts.length - 1]
      if (last === "desktop" || last === "client" || last === "app")
        last = parts[parts.length - 2] || last
      name = last
    }
    name = name.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim()
    return name ? name.charAt(0).toUpperCase() + name.slice(1) : "App"
  }

  function isScrollingWorkspace() {
    var ipc = root.workspace ? root.workspace.lastIpcObject : null
    return !!ipc && String(ipc.tiledLayout || "") === "scrolling"
  }

  function focusWindow(win) {
    var address = win && win.address ? String(win.address) : ""
    if (!address) return
    if (address.indexOf("0x") !== 0) address = "0x" + address

    var focus = 'hl.dsp.focus({ window = hl.get_window("address:' + address + '") })'
    var command = "hyprctl dispatch " + Util.shellQuote(focus)

    // "center" is a scrolling-layout message: it centers the focused column.
    // Sending it on dwindle/master would only log an unknown-message error.
    if (root.isScrollingWorkspace())
      command += " && hyprctl dispatch " + Util.shellQuote('hl.dsp.layout("center")')

    if (root.bar) root.bar.run(command)
    else Util.execDetached(command)
  }

  readonly property color foregroundColor: root.bar ? root.bar.barForeground : Color.bar.text
  readonly property int pillHeight: Math.max(16, root.barSize - Style.space(6))

  visible: !vertical && windows.length > 0
  implicitWidth: visible ? row.implicitWidth + Style.space(8) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)

    Repeater {
      model: root.windows

      delegate: Rectangle {
        id: pill
        required property var modelData

        readonly property bool focused: modelData.activated === true
        readonly property bool hovered: mouseArea.containsMouse

        width: Math.min(root.maxLabelWidth, label.implicitWidth)
          + Style.spacing.controlPaddingX * 2
        height: root.pillHeight
        radius: Style.space(4)
        color: focused
          ? Util.alpha(root.foregroundColor, 0.22)
          : (hovered ? Util.alpha(root.foregroundColor, 0.12)
                     : Util.alpha(root.foregroundColor, 0.05))
        border.width: focused ? Style.normalBorderWidth : 0
        border.color: Util.alpha(root.foregroundColor, 0.30)

        Text {
          id: label
          anchors.centerIn: parent
          width: Math.min(root.maxLabelWidth, implicitWidth)
          text: root.labelFor(pill.modelData)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.foregroundColor
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: pill.focused
        }

        MouseArea {
          id: mouseArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.PointingHandCursor

          onClicked: root.focusWindow(pill.modelData)
          onEntered: if (root.bar) root.bar.showTooltip(
            pill,
            pill.modelData.title || root.labelFor(pill.modelData)
          )
          onExited: if (root.bar) root.bar.hideTooltip(pill)
        }
      }
    }
  }
}
