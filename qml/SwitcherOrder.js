.pragma library
.import "FuzzyMatch.js" as Fuzzy

// Ordering and filtering for the window switcher. Pure (no QML types), so
// qmltestrunner pins the behaviour; the component snapshots Hyprland's
// toplevels into plain entries ({ address, title, class, workspaceId,
// workspaceName, focusHistoryID, ... }) before calling in.

// The focused workspace's windows first, everything else after; each group
// keeps the MRU order it arrived in.
function order(entries, activeWorkspaceId) {
    var here = [];
    var elsewhere = [];
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].workspaceId === activeWorkspaceId)
            here.push(entries[i]);
        else
            elsewhere.push(entries[i]);
    }
    return here.concat(elsewhere);
}

// Most-recently-used first, from Hyprland's focusHistoryID (0 is the focused
// window). Entries without one sort last, keeping their arrival order.
function byRecency(entries) {
    var indexed = [];
    for (var i = 0; i < entries.length; i++) {
        var history = entries[i].focusHistoryID;
        indexed.push({
            entry: entries[i],
            history: typeof history === "number" ? history : Number.MAX_SAFE_INTEGER,
            position: i,
        });
    }
    indexed.sort(function(a, b) {
        return a.history !== b.history ? a.history - b.history : a.position - b.position;
    });
    var ordered = [];
    for (var i = 0; i < indexed.length; i++)
        ordered.push(indexed[i].entry);
    return ordered;
}

// The rows a query leaves: a subsequence match over the window title, class
// and workspace name. An empty query keeps everything, in order.
function filter(entries, query) {
    if (!query || query.length === 0)
        return entries.slice();
    var rows = [];
    for (var i = 0; i < entries.length; i++) {
        if (score(entries[i], query) >= 0)
            rows.push(entries[i]);
    }
    return rows;
}

function score(entry, query) {
    var best = Fuzzy.score(query, entry.title);
    best = Math.max(best, Fuzzy.score(query, entry.class));
    best = Math.max(best, Fuzzy.score(query, entry.workspaceName));
    return best;
}
