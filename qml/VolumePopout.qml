// Audio popout: output (sink) and input (source) level meters, volume sliders
// and mute toggles for the default devices, plus a headphone/speaker/mic icon.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: popout

    required property Theme theme

    // The owner opens/closes us (hover-with-delay or click); hover over the
    // popout itself reports back so it stays open while the pointer is inside.
    property bool open: false
    // Pinned (click-opened) popouts close only when focus is lost.
    property bool pinned: false
    signal focusLost()
    readonly property bool hovered: popupHover.hovered

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinkAudio: sink && sink.audio ? sink.audio : null
    readonly property var sourceAudio: source && source.audio ? source.audio : null

    function deviceName(node): string {
        if (!node)
            return "No device";
        return node.description || node.nickname || node.name || "Unknown device";
    }

    function isHeadphones(node): bool {
        if (!node)
            return false;
        var properties = node.properties || ({});
        var hint = ((properties["device.icon-name"] || "") + " " + (node.name || "") + " " + (node.description || "")).toLowerCase();
        return hint.indexOf("headphone") >= 0 || hint.indexOf("headset") >= 0;
    }

    function outputGlyph(node, muted): string {
        if (!node)
            return "󰝟";
        if (isHeadphones(node))
            return "\uf025";
        if (muted)
            return "󰝟";
        var volume = node.audio ? node.audio.volume : 0;
        return volume <= 0.33 ? "󰕿" : volume <= 0.66 ? "󰖀" : "󰕾";
    }

    visible: open
    implicitWidth: 320
    implicitHeight: layout.implicitHeight + 24
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-audio"

    anchors {
        top: true
        right: true
    }
    margins.top: 38
    margins.right: 8

    // A click-opened (pinned) popout closes when it loses focus.
    HyprlandFocusGrab {
        active: popout.open && popout.pinned
        windows: [popout]
        onCleared: popout.focusLost()
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    PwNodePeakMonitor {
        id: sinkPeaks

        node: Pipewire.defaultAudioSink
        enabled: popout.open
    }

    PwNodePeakMonitor {
        id: sourcePeaks

        node: Pipewire.defaultAudioSource
        enabled: popout.open
    }

    component Meter: Column {
        id: meter

        property var monitor
        readonly property int count: monitor && monitor.peaks ? Math.max(1, monitor.peaks.length) : 1

        spacing: 2

        Repeater {
            model: meter.count

            Rectangle {
                required property int index

                width: meter.width
                height: 4
                radius: 2
                color: popout.theme.base

                Rectangle {
                    width: parent.width * Math.min(1, meter.monitor && meter.monitor.peaks ? meter.monitor.peaks[index] : 0)
                    height: parent.height
                    radius: 2
                    color: popout.theme.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        }
    }

    component LevelSlider: Item {
        id: slider

        property real value: 0
        signal moved(real value)

        implicitHeight: 18

        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: popout.theme.base
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: track.width * Math.max(0, Math.min(1, slider.value))
            height: 4
            radius: 2
            color: popout.theme.accent
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: track.width * Math.max(0, Math.min(1, slider.value)) - width / 2
            width: 12
            height: 12
            radius: 6
            color: popout.theme.text
        }

        MouseArea {
            anchors.fill: parent

            function setFromX(x) {
                slider.moved(Math.max(0, Math.min(1, x / width)));
            }

            onPressed: mouse => setFromX(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    setFromX(mouse.x);
            }
        }
    }

    component MuteButton: Text {
        id: mute

        property bool muted
        property string onGlyph: "󰕾"
        property string offGlyph: "󰝟"
        signal toggled()

        color: hover.containsMouse ? popout.theme.accent : popout.theme.text
        font.family: popout.theme.fontFamily
        font.pixelSize: 16
        text: muted ? offGlyph : onGlyph

        MouseArea {
            id: hover

            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            onClicked: mute.toggled()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: popout.theme.radius
        color: popout.theme.surface
        border.width: 1
        border.color: popout.theme.surfaceAlt

        Item {
            anchors.fill: parent

            Column {
                id: layout

                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                    rightMargin: 12
                }
                spacing: 6

                Text {
                    text: "Output"
                    color: popout.theme.subtext
                    font.family: popout.theme.fontFamily
                    font.pixelSize: 11
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 16
                        text: popout.outputGlyph(popout.sink, popout.sinkAudio ? popout.sinkAudio.muted : false)
                    }

                    Text {
                        width: parent.width - 16 - 8 - muteOut.width
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: popout.deviceName(popout.sink)
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 12
                    }

                    MuteButton {
                        id: muteOut

                        muted: popout.sinkAudio ? popout.sinkAudio.muted : false
                        onToggled: if (popout.sinkAudio)
                            popout.sinkAudio.muted = !popout.sinkAudio.muted
                    }
                }

                Meter {
                    width: parent.width
                    monitor: sinkPeaks
                }

                Row {
                    width: parent.width
                    spacing: 10

                    LevelSlider {
                        width: parent.width - 40
                        value: popout.sinkAudio ? popout.sinkAudio.volume : 0
                        onMoved: value => {
                            if (popout.sinkAudio) {
                                popout.sinkAudio.muted = false;
                                popout.sinkAudio.volume = value;
                            }
                        }
                    }

                    Text {
                        width: 30
                        horizontalAlignment: Text.AlignRight
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 12
                        text: (popout.sinkAudio ? Math.round(popout.sinkAudio.volume * 100) : 0) + "%"
                    }
                }

                Text {
                    text: "Input"
                    color: popout.theme.subtext
                    font.family: popout.theme.fontFamily
                    font.pixelSize: 11
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 16
                        text: popout.sourceAudio && popout.sourceAudio.muted ? "\uf131" : "\uf130"
                    }

                    Text {
                        width: parent.width - 16 - 8 - muteIn.width
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: popout.deviceName(popout.source)
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 12
                    }

                    MuteButton {
                        id: muteIn

                        onGlyph: "\uf130"
                        offGlyph: "\uf131"
                        muted: popout.sourceAudio ? popout.sourceAudio.muted : false
                        onToggled: if (popout.sourceAudio)
                            popout.sourceAudio.muted = !popout.sourceAudio.muted
                    }
                }

                Meter {
                    width: parent.width
                    monitor: sourcePeaks
                }

                Row {
                    width: parent.width
                    spacing: 10

                    LevelSlider {
                        width: parent.width - 40
                        value: popout.sourceAudio ? popout.sourceAudio.volume : 0
                        onMoved: value => {
                            if (popout.sourceAudio) {
                                popout.sourceAudio.muted = false;
                                popout.sourceAudio.volume = value;
                            }
                        }
                    }

                    Text {
                        width: 30
                        horizontalAlignment: Text.AlignRight
                        color: popout.theme.text
                        font.family: popout.theme.fontFamily
                        font.pixelSize: 12
                        text: (popout.sourceAudio ? Math.round(popout.sourceAudio.volume * 100) : 0) + "%"
                    }
                }
            }
        }
    }

    // Hover tracking only; does not consume presses, so the sliders still work.
    Item {
        anchors.fill: parent

        HoverHandler {
            id: popupHover
        }
    }
}
