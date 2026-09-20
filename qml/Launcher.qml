// Application launcher: a layer-shell overlay toggled by the qshell bridge.
//
// A plain query lists desktop entries (subsequence match, ranked by launch
// frequency then recency then score; state in
// `$XDG_STATE_HOME/quickshell/launcher.json`) followed by "run" entries for the
// whole line: `=` raw, `>` in a terminal, `>>` in a terminal kept open. `?`
// searches files under `$HOME` (mime icons; opened with the default handler,
// or the editor in a terminal).
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: launcher

    required property Theme theme

    visible: false
    // Visual state: the launcher animates itself (backdrop fades, card scales)
    // and Hyprland is told not to animate the surface (`no_anim`), so `visible`
    // only maps/unmaps, a beat after the close animation.
    property bool shown: false
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-launcher"

    property var results: []
    property int current: 0
    // Distinguishes a loaded state file (writes allowed) from the initial
    // adapter population, which must not be written straight back.
    property bool stateReady: false
    property string filePattern: ""

    readonly property string fileRoot: Quickshell.env("HOME") || "/"

    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") || "/tmp") + "/.local/state"
    // A command prefix that runs the following argv in a terminal, e.g.
    // "foot -e" or "xdg-terminal-exec". Space-separated; no emulator is
    // assumed by the shell.
    readonly property string terminal: Quickshell.env("QSHELL_TERMINAL")
        || Quickshell.env("TERMINAL")
        || "xdg-terminal-exec"
    readonly property string editor: Quickshell.env("QSHELL_EDITOR")
        || Quickshell.env("EDITOR")
        || Quickshell.env("VISUAL")
        || "nvim"
    // Exit 0 when the mime's default handler is a GUI application, 1 when it is
    // a terminal application or there is no handler (either way we fall back to
    // the editor in a terminal). `xdg-open` itself cannot be used to decide:
    // it does not return in this environment.
    readonly property string handlerScript: 'app=$(xdg-mime query default "$(xdg-mime query filetype "$1" 2>/dev/null)" 2>/dev/null); [ -n "$app" ] || exit 1; IFS=:; for d in ${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do f="$d/applications/$app"; [ -f "$f" ] || continue; grep -qi "^Terminal=true" "$f" && exit 1; exit 0; done; exit 1'

    function terminalPrefix(): var {
        return terminal.length > 0 ? terminal.split(" ") : [];
    }

    Timer {
        id: closeTimer

        interval: 170
        onTriggered: launcher.visible = false
    }

    function open(): void {
        closeTimer.stop();
        visible = true;
        shown = true;
        field.text = "";
        recompute();
        scope.forceActiveFocus();
        field.forceActiveFocus();
    }

    function close(): void {
        shown = false;
        closeTimer.restart();
    }

    function toggle(): void {
        if (shown)
            close();
        else
            open();
    }

    function move(delta: int): void {
        if (results.length === 0)
            return;
        current = (current + delta + results.length) % results.length;
        list.positionViewAtIndex(current, ListView.Contain);
    }

    function activate(index: int): void {
        if (index < 0 || index >= results.length)
            return;
        var item = results[index];
        close();
        if (item.kind === "run") {
            run(item);
        } else if (item.kind === "file") {
            openFile(item.path);
        } else {
            recordLaunch(item.entry.id);
            launch(item.entry);
        }
    }

    function run(item): void {
        var prefix = item.terminal ? terminalPrefix() : [];
        // `keepOpen` runs the command in the terminal and then drops to a
        // shell, instead of the terminal exiting with the command.
        var command = item.keepOpen ? item.command + '; exec "${SHELL:-sh}"' : item.command;
        Quickshell.execDetached(prefix.concat(["sh", "-c", command]));
    }

    function openFile(path): void {
        fileHandler.target = path;
        fileHandler.command = ["sh", "-c", handlerScript, "sh", path];
        fileHandler.running = true;
    }

    function launch(entry): void {
        var command = entry.command.slice();
        if (entry.runInTerminal)
            command = terminalPrefix().concat(command);
        Quickshell.execDetached(["uwsm", "app", "--"].concat(command));
    }

    function recordLaunch(id): void {
        var next = {};
        var previous = state.apps || {};
        for (var key in previous)
            next[key] = previous[key];
        var record = next[id] || { count: 0, last: 0 };
        next[id] = { count: record.count + 1, last: Date.now() };
        state.apps = next;
    }

    function runItem(command, terminal, keepOpen): var {
        return { kind: "run", command: command, terminal: terminal, keepOpen: keepOpen };
    }

    function recompute(): void {
        // Read the field directly rather than a bound property: onTextChanged
        // fires before such a binding necessarily reflects the new text.
        var text = field.text;

        if (text.length > 0 && text.charAt(0) === "?") {
            requestFileSearch(text.substring(1).trim());
            return;
        }
        fileSearch.running = false;

        if (text.indexOf(">>") === 0) {
            var kept = text.substring(2).trim();
            results = kept.length > 0 ? [runItem(kept, true, true)] : [];
            current = 0;
            return;
        }

        var raw = text.length > 0 && text.charAt(0) === "=";
        var inTerminal = text.length > 0 && text.charAt(0) === ">";
        if (raw || inTerminal) {
            var command = text.substring(1).trim();
            results = command.length > 0 ? [runItem(command, inTerminal, false)] : [];
            current = 0;
            return;
        }

        var needle = text.toLowerCase();
        var entries = DesktopEntries.applications.values;
        var ranked = [];

        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            var score = needle.length === 0 ? 0 : scoreEntry(needle, entry);
            if (score < 0)
                continue;
            var record = state.apps && state.apps[entry.id] ? state.apps[entry.id] : null;
            ranked.push({
                kind: "app",
                entry: entry,
                score: score,
                count: record ? record.count : 0,
                last: record ? record.last : 0,
            });
        }

        ranked.sort(byRank);

        // The whole line (flags and all) is offered as a command, after the
        // matching applications.
        var line = text.trim();
        if (line.length > 0) {
            ranked.push(runItem(line, false, false));
            ranked.push(runItem(line, true, false));
            ranked.push(runItem(line, true, true));
        }

        results = ranked;
        current = 0;
    }

    function requestFileSearch(pattern): void {
        filePattern = pattern;
        if (pattern.length === 0) {
            results = [];
            current = 0;
            return;
        }
        fileDebounce.restart();
    }

    function runFileSearch(): void {
        fileSearch.command = ["fd", "--type", "f", "--fixed-strings", "--max-results", "50", filePattern, fileRoot];
        fileSearch.running = true;
    }

    function applyFileResults(output): void {
        // Ignore output from a search the query has already moved past.
        if (field.text.charAt(0) !== "?" || field.text.substring(1).trim() !== filePattern)
            return;
        var lines = output.split("\n");
        var files = [];
        var paths = [];
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                files.push({ kind: "file", path: lines[i], mime: "" });
                paths.push(lines[i]);
            }
        }
        results = files;
        current = 0;
        if (paths.length > 0) {
            fileMime.command = ["file", "--mime-type", "-b", "--"].concat(paths);
            fileMime.running = true;
        }
    }

    function applyFileMimes(output): void {
        if (field.text.charAt(0) !== "?" || field.text.substring(1).trim() !== filePattern)
            return;
        var mimes = output.split("\n");
        var updated = [];
        for (var i = 0; i < results.length; i++) {
            var item = results[i];
            if (item.kind !== "file")
                return;
            updated.push({ kind: "file", path: item.path, mime: i < mimes.length ? mimes[i].trim() : "" });
        }
        results = updated;
    }

    function byRank(a, b): int {
        if (b.count !== a.count)
            return b.count - a.count;
        if (b.last !== a.last)
            return b.last - a.last;
        if (b.score !== a.score)
            return b.score - a.score;
        return a.entry.name.localeCompare(b.entry.name);
    }

    // Bonuses consecutive characters and word starts; penalises late and long
    // haystacks. Returns -1 when the query is not a subsequence.
    function fuzzy(needle, haystack): real {
        if (!haystack)
            return -1;
        var text = haystack.toLowerCase();
        var from = 0;
        var score = 0;
        var streak = 0;
        var first = -1;
        for (var i = 0; i < needle.length; i++) {
            var at = text.indexOf(needle.charAt(i), from);
            if (at === -1)
                return -1;
            if (first === -1)
                first = at;
            streak = at === from ? streak + 1 : 0;
            score += 1 + streak;
            var before = at === 0 ? "" : text.charAt(at - 1);
            if (before === "" || before === " " || before === "-" || before === "_")
                score += 3;
            from = at + 1;
        }
        return score - first * 0.5 - text.length * 0.01;
    }

    function scoreEntry(needle, entry): real {
        var best = fuzzy(needle, entry.name);
        var generic = fuzzy(needle, entry.genericName);
        if (generic >= 0)
            best = Math.max(best, generic * 0.7);
        var comment = entry.comment ? fuzzy(needle, entry.comment) : -1;
        if (comment >= 0)
            best = Math.max(best, comment * 0.4);
        for (var i = 0; i < entry.keywords.length; i++) {
            var keyword = fuzzy(needle, entry.keywords[i]);
            if (keyword >= 0)
                best = Math.max(best, keyword * 0.6);
        }
        return best;
    }

    function iconSource(item): string {
        if (item.kind === "run")
            return Quickshell.iconPath("utilities-terminal", "application-x-executable");
        if (item.kind === "file")
            return mimeIcon(item.mime);
        return Quickshell.iconPath(item.entry.icon || "application-x-executable", "application-x-executable");
    }

    function mimeIcon(mime): string {
        if (!mime)
            return Quickshell.iconPath("text-x-generic", "application-x-executable");
        var generic = "text-x-generic";
        if (mime.indexOf("image/") === 0)
            generic = "image-x-generic";
        else if (mime.indexOf("video/") === 0)
            generic = "video-x-generic";
        else if (mime.indexOf("audio/") === 0)
            generic = "audio-x-generic";
        else if (mime.indexOf("font/") === 0)
            generic = "font-x-generic";
        else if (mime.indexOf("application/") === 0)
            generic = "application-x-generic";
        return Quickshell.iconPath(mime.replace("/", "-"), generic);
    }

    function title(item): string {
        if (item.kind === "run")
            return item.command;
        if (item.kind === "file")
            return item.path.substring(item.path.lastIndexOf("/") + 1);
        return item.entry.name;
    }

    function subtitle(item): string {
        if (item.kind === "run") {
            if (item.keepOpen)
                return "Run in terminal (keep open)";
            return item.terminal ? "Run in terminal" : "Run command";
        }
        if (item.kind === "file") {
            var slash = item.path.lastIndexOf("/");
            return slash > 0 ? item.path.substring(0, slash) : item.path;
        }
        return item.entry.genericName || item.entry.comment || "";
    }

    // The state file is written atomically by FileView, but its directory is
    // ours to make.
    Process {
        command: ["mkdir", "-p", launcher.stateHome + "/quickshell"]
        running: true
    }

    FileView {
        id: stateFile

        path: launcher.stateHome + "/quickshell/launcher.json"
        onLoaded: {
            launcher.stateReady = true;
            launcher.recompute();
        }
        onLoadFailed: {
            launcher.stateReady = true;
            launcher.recompute();
        }
        onAdapterUpdated: {
            if (launcher.stateReady)
                writeAdapter();
        }

        JsonAdapter {
            id: state

            property var apps: ({})
        }
    }

    Process {
        id: fileSearch

        stdout: StdioCollector {
            onStreamFinished: launcher.applyFileResults(this.text)
        }
    }

    Process {
        id: fileMime

        stdout: StdioCollector {
            onStreamFinished: launcher.applyFileMimes(this.text)
        }
    }

    // Open a file with its default handler; if it needs a terminal (or there is
    // no handler), open it with the editor in a terminal instead.
    Process {
        id: fileHandler

        property string target: ""

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                Quickshell.execDetached(["xdg-open", fileHandler.target]);
            else
                Quickshell.execDetached(launcher.terminalPrefix().concat(launcher.editor.split(" ")).concat([fileHandler.target]));
        }
    }

    Timer {
        id: fileDebounce

        interval: 160
        onTriggered: launcher.runFileSearch()
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged(): void {
            launcher.recompute();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: launcher.theme.backdrop
        opacity: launcher.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: launcher.close()
        }
    }

    FocusScope {
        id: scope

        anchors.fill: parent
        focus: true

        Rectangle {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 120
            width: 600
            height: layout.implicitHeight + 16
            radius: launcher.theme.radius
            color: launcher.theme.surface
            border.width: 1
            border.color: launcher.theme.border
            scale: launcher.shown ? 1 : 0.96
            opacity: launcher.shown ? 1 : 0

            Behavior on scale {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.1
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutQuad
                }
            }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: layout

                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 8
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                TextField {
                    id: field

                    width: parent.width
                    height: 44
                    color: launcher.theme.text
                    placeholderText: "Search applications…  (= run, > terminal, >> keep, ? files)"
                    placeholderTextColor: launcher.theme.overlay
                    font.family: launcher.theme.fontFamily
                    font.pixelSize: launcher.theme.fontSize
                    leftPadding: 12
                    rightPadding: 12
                    selectByMouse: true
                    background: Rectangle {
                        radius: launcher.theme.itemRadius
                        color: launcher.theme.base
                        border.width: 1
                        border.color: field.activeFocus ? launcher.theme.accent : launcher.theme.border
                    }
                    onTextChanged: launcher.recompute()
                    onAccepted: launcher.activate(launcher.current)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            launcher.close();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            launcher.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            launcher.move(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            launcher.move(6);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            launcher.move(-6);
                            event.accepted = true;
                        }
                    }
                }

                ListView {
                    id: list

                    width: parent.width
                    height: launcher.results.length > 0 ? Math.min(8, launcher.results.length) * 48 : 0
                    visible: launcher.results.length > 0
                    clip: true
                    model: launcher.results
                    currentIndex: launcher.current
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: ListView.view.width
                        height: 48
                        radius: launcher.theme.itemRadius
                        color: index === launcher.current ? launcher.theme.surfaceAlt : (hover.containsMouse ? launcher.theme.surfaceAlt : "transparent")

                        Row {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: 10
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 12

                            Image {
                                width: 24
                                height: 24
                                sourceSize: Qt.size(24, 24)
                                source: launcher.iconSource(modelData)
                                visible: source !== ""
                            }

                            Column {
                                width: parent.width - 36
                                spacing: 1

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    color: launcher.theme.text
                                    font.family: launcher.theme.fontFamily
                                    font.pixelSize: launcher.theme.fontSize
                                    text: launcher.title(modelData)
                                }

                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                    color: launcher.theme.overlay
                                    font.family: launcher.theme.fontFamily
                                    font.pixelSize: launcher.theme.fontSizeSmall
                                    text: launcher.subtitle(modelData)
                                }
                            }
                        }

                        MouseArea {
                            id: hover

                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: launcher.activate(index)
                        }
                    }
                }
            }
        }
    }
}
