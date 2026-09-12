#!/usr/bin/env bash
# Lance tous les essais automatises du projet.
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

run() {
	echo
	echo "=== $1 ==="
	if "$GODOT" --headless --path "$PROJECT_DIR" --quit-after 900 "$2"; then
		:
	else
		FAILED=1
	fi
}

"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true
run "Geometrie du trace" res://tools/tests/test_track_plan.tscn
run "Physique du vehicule" res://tools/tests/physics_test.tscn
run "Animation des roues" res://tools/tests/visuals_test.tscn

echo
if [ "$FAILED" -eq 0 ]; then
	echo "Tous les essais passent."
else
	echo "Des essais ont echoue." >&2
fi
exit "$FAILED"
