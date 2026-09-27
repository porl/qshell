import QtQuick
import QtTest
import "../qml/SwitcherOrder.js" as Order

// The switcher's pure ordering and filtering (qml/SwitcherOrder.js). The
// component snapshots Hyprland's toplevels into plain entries before calling
// in, so the policy is testable without a compositor.
TestCase {
    name: "SwitcherOrder"

    function entry(address, workspaceId, history, title, cls) {
        return {
            address: address,
            workspaceId: workspaceId,
            focusHistoryID: history,
            title: title || "",
            class: cls || "",
            workspaceName: "",
        };
    }

    function addresses(entries) {
        return entries.map(e => e.address).join(",");
    }

    function test_focused_workspace_first() {
        var entries = [
            entry("a", 1, 0),
            entry("b", 2, 1),
            entry("c", 1, 2),
            entry("d", 3, 3),
        ];
        compare(addresses(Order.order(entries, 1)), "a,c,b,d");
        compare(addresses(Order.order(entries, 2)), "b,a,c,d");
        compare(addresses(Order.order(entries, 9)), "a,b,c,d");
    }

    function test_order_keeps_mru_within_groups() {
        var entries = [entry("x", 5, 0), entry("y", 5, 1), entry("z", 4, 2)];
        // Both x and y are elsewhere; their arrival order (MRU) is untouched.
        compare(addresses(Order.order(entries, 1)), "x,y,z");
    }

    function test_recency_sorts_by_focus_history() {
        var entries = [entry("a", 1, 3), entry("b", 1, 0), entry("c", 1, 2), entry("d", 1, 1)];
        compare(addresses(Order.byRecency(entries)), "b,d,c,a");
    }

    function test_recency_missing_history_sorts_last() {
        var entries = [entry("a", 1, 5), entry("b", 1, undefined), entry("c", 1, 0)];
        compare(addresses(Order.byRecency(entries)), "c,a,b");
    }

    function test_recency_is_stable_for_equal_history() {
        var entries = [entry("a", 1, 1), entry("b", 1, 1)];
        compare(addresses(Order.byRecency(entries)), "a,b");
    }

    function test_filter_empty_query_keeps_everything() {
        var entries = [entry("a", 1, 0, "Firefox"), entry("b", 1, 1, "Foot")];
        compare(addresses(Order.filter(entries, "")), "a,b");
    }

    function test_filter_matches_title_class_and_workspace() {
        var entries = [
            { address: "a", title: "Inbox — Thunderbird", class: "thunderbird", workspaceName: "1" },
            { address: "b", title: "nvim notes.md", class: "foot", workspaceName: "2" },
        ];
        compare(addresses(Order.filter(entries, "thunder")), "a");
        compare(addresses(Order.filter(entries, "foot")), "b");
        compare(addresses(Order.filter(entries, "inbox")), "a");
        compare(addresses(Order.filter(entries, "zzz")), "");
    }

    function test_filter_preserves_order() {
        var entries = [entry("a", 1, 0, "alpha"), entry("b", 1, 1, "alpine"), entry("c", 1, 2, "beta")];
        compare(addresses(Order.filter(entries, "al")), "a,b");
    }
}
