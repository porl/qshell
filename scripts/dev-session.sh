#!/usr/bin/env bash
# Run the session shell from the working tree in the current Wayland session.
# Development only: it starts a second shell over any running one. Stop with
# Ctrl+C. Needs cargo (run inside `nix develop`).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
qcommon="${QSHELL_COMMON:-$repo/../qcommon/qml}"

if ! command -v cargo >/dev/null 2>&1; then
    echo "dev-session: cargo not found; run this inside 'nix develop'." >&2
    exit 1
fi

# The shared components live in qcommon; merge the two trees so the QML
# resolves by name, matching the packaged tree.
merged="$(mktemp -d)"
trap 'rm -rf "$merged"' EXIT
cp -r "$qcommon"/. "$merged"/
cp -r "$repo/qml"/. "$merged"/

export QSHELL_QML="${QSHELL_QML:-$merged}"
export QSHELL_SOCKET="${QSHELL_SOCKET:-${XDG_RUNTIME_DIR:-/tmp}/qshell.sock}"

cargo run --manifest-path "$repo/Cargo.toml" -- "$@"
