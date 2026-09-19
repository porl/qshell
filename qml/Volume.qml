// Volume block: shows the default sink's mute state and level. Click toggles
// mute, scroll adjusts the level. Bound through Quickshell's PipeWire service
// (tracked so updates arrive without polling).
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Text {
    id: volume

    required property Theme theme

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink && sink.audio ? sink.audio : null
    readonly property bool muted: audio ? audio.muted : false
    readonly property int percent: audio ? Math.round(audio.volume * 100) : 0
    readonly property string glyph: {
        if (!audio || muted || percent === 0)
            return "󰝟";
        if (percent <= 33)
            return "󰕿";
        if (percent <= 66)
            return "󰖀";
        return "󰕾";
    }

    property PopoutState popout: PopoutState {}

    color: hover.containsMouse || popout.open ? theme.accent : theme.text
    font.family: theme.fontFamily
    font.pixelSize: 12
    text: glyph + " " + (audio ? percent + "%" : "--")

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    MouseArea {
        id: hover

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onContainsMouseChanged: containsMouse ? volume.popout.anchorEntered() : volume.popout.anchorExited()
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                // Mute is a transient action: open, but fade out on mouse-out.
                volume.popout.hoverActivate();
                if (volume.audio)
                    volume.audio.muted = !volume.audio.muted;
            } else {
                // Left/right click pins the popout until focus is lost.
                volume.popout.activate();
            }
        }
        onWheel: event => {
            volume.popout.hoverActivate();
            if (!volume.audio)
                return;
            const delta = (event.angleDelta.y / 120) * 0.05;
            volume.audio.muted = false;
            volume.audio.volume = Math.max(0, Math.min(1, volume.audio.volume + delta));
        }
    }

    VolumePopout {
        theme: volume.theme
        open: volume.popout.open
        pinned: volume.popout.pinned
        onHoveredChanged: hovered ? volume.popout.contentEntered() : volume.popout.contentExited()
        onFocusLost: volume.popout.focusLost()
    }
}
