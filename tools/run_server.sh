#!/usr/bin/env bash
# Lance le serveur dedie, sans affichage.
#
#   tools/run_server.sh                 port et transport de tuning.cfg
#   tools/run_server.sh 8910 websocket  port et transport explicites
#
# Variable GODOT : chemin de l'executable Godot si absent du PATH.
set -euo pipefail

GODOT="${GODOT:-godot}"
PORT="${1:-}"
TRANSPORT="${2:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ARGS=(--server --diagnostics)
[[ -n "$PORT" ]] && ARGS+=(--port "$PORT")
[[ -n "$TRANSPORT" ]] && ARGS+=(--transport "$TRANSPORT")

echo "Serveur dedie : ${ARGS[*]}"
exec "$GODOT" --headless --path "$PROJECT_DIR" -- "${ARGS[@]}"
