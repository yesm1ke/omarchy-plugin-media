import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "io.github.yesm1ke.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("io.github.yesm1ke.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []
  readonly property bool cliampRunning: mediaService ? mediaService.cliampRunning : false

  function startCliamp() {
    if (root.bar) root.bar.run("cliamp -d")
  }

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  property bool popupOpen: false
  property bool hovered: false

  // Panel-hotkey contract (SUPER+CTRL+1-9 / Bar.qml:findPanelWidget): a widget
  // only gets a slot number if it exposes open()/close()/opened under those
  // exact names, which popupOpen isn't.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  property real maxLabelWidth: 200

  // Keyboard navigation inside the popup: a flat cursor over prev/playPause/
  // next, then Start Cliamp (only while it's actually offered), then the
  // source-player rows (only when there's more than one, matching their
  // existing visibility). PopupCard/PopupWindow (xdg-popup) never receives
  // key events unless a click already routed focus through the parent
  // surface first, which is why Escape and arrow keys did nothing when the
  // popup was opened via SUPER+CTRL+1 -- KeyboardPanel below exists
  // specifically to grab focus on open instead.
  property int cursorIndex: 0
  property bool cursorActive: false
  readonly property int startCliampIndex: 3
  readonly property int sourceBaseIndex: cliampRunning ? 3 : 4
  readonly property int sourceCount: sourcePlayers.length > 1 ? sourcePlayers.length : 0
  readonly property int cursorCount: 3 + (cliampRunning ? 0 : 1) + sourceCount

  onPopupOpenChanged: {
    if (!popupOpen) return
    cursorActive = false
    cursorIndex = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    var n = root.cursorCount
    if (n <= 0) return
    var delta = dy !== 0 ? dy : dx
    cursorIndex = ((cursorIndex + delta) % n + n) % n
  }

  function activateCursor() {
    cursorActive = true
    var i = cursorIndex
    if (i === 0) {
      if (root.activePlayer && root.activePlayer.canGoPrevious && root.mediaService)
        root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
      return
    }
    if (i === 1) {
      if (root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause) && root.mediaService)
        root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
      return
    }
    if (i === 2) {
      if (root.activePlayer && root.activePlayer.canGoNext && root.mediaService)
        root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
      return
    }
    if (!root.cliampRunning && i === root.startCliampIndex) {
      root.startCliamp()
      return
    }
    var sourceIndex = i - root.sourceBaseIndex
    if (sourceIndex >= 0 && sourceIndex < root.sourcePlayers.length) {
      var player = root.sourcePlayers[sourceIndex]
      if (root.mediaService && player) root.mediaService.selectPlayer(root.mediaService.playerKey(player))
    }
  }

  // Always visible (not gated on hasMedia) so there's a click target to start
  // Cliamp from cold -- otherwise there'd be nothing on the bar to click when
  // no player is running at all.
  visible: true
  implicitHeight: barSize

  // Title reveal, done the way the stock tray drawer does it: one eased
  // progress value (same 600 ms OutCubic), everything else derived from it and
  // snapped to whole pixels. Animating the clip width directly, centring the
  // row and toggling `visible` made the bar relayout at fractional offsets,
  // cut the collapse short and restart the scroll mid-reveal.
  readonly property int animationDuration: 600
  readonly property bool showLabel: !root.bar.vertical && root.title !== ""
  readonly property int labelExtent: showLabel ? Math.ceil(Math.min(root.maxLabelWidth, labelText.implicitWidth)) : 0
  property real revealProgress: root.hovered && showLabel ? 1 : 0
  readonly property int revealExtent: Math.round(labelExtent * revealProgress)
  readonly property bool revealed: revealProgress >= 1

  Behavior on revealProgress {
    NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
  }

  readonly property int padding: Math.round(Style.space(7))
  implicitWidth: padding * 2 + Math.ceil(glyph.implicitWidth)
    + (revealExtent > 0 ? Math.round(Style.space(6)) + revealExtent : 0)

  Row {
    id: row
    x: root.padding
    anchors.verticalCenter: parent.verticalCenter
    spacing: root.revealExtent > 0 ? Math.round(Style.space(6)) : 0

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: scrollClip
      width: root.revealExtent
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: root.revealExtent > 0

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
        x: 0

        property bool needsScroll: implicitWidth > root.labelExtent

        // Scroll only once the reveal has finished, starting from the resting
        // position, and snap back when it stops so the next reveal starts clean.
        SequentialAnimation {
          id: scrollAnim
          running: root.revealed && root.hovered && labelText.needsScroll && !root.popupOpen
          loops: Animation.Infinite
          onRunningChanged: if (!running) labelText.x = 0
          PauseAnimation { duration: 1200 }
          NumberAnimation {
            target: labelText; property: "x"
            from: 0; to: -labelText.implicitWidth
            duration: Math.max(3000, labelText.implicitWidth * 25)
            easing.type: Easing.Linear
          }
          NumberAnimation {
            target: labelText; property: "x"
            from: root.labelExtent; to: 0
            duration: Math.max(1000, root.labelExtent * 25)
            easing.type: Easing.Linear
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      // Right click always opens the popup -- it's the only way to reach the
      // Start Cliamp button when nothing is playing yet. Left/middle click
      // still need a real player to act on.
      if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
        return
      }
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: root.hovered = true
    onExited: root.hovered = false
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            textFormat: Text.PlainText
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          hasCursor: root.cursorActive && root.cursorIndex === 0
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          hasCursor: root.cursorActive && root.cursorIndex === 1
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          hasCursor: root.cursorActive && root.cursorIndex === 2
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
      }

      Button {
        text: "Start Cliamp"
        visible: !root.cliampRunning
        foreground: root.bar.foreground
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        width: parent.width
        hasCursor: root.cursorActive && root.cursorIndex === root.startCliampIndex
        onClicked: root.startCliamp()
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData
            required property int index

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property bool cursorHere: root.cursorActive && root.cursorIndex === (root.sourceBaseIndex + index)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent)
              : (cursorHere ? Border.controlSpec("focus", root.bar.foreground, Color.accent) : Border.none())

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
    }
  }
}
