#!/usr/bin/env bash
# Lance un serveur dedie et deux clients sur la meme machine, pour verifier que
# deux joueurs se voient rouler.
#
#   tools/run_two_clients.sh          sans latence
#   tools/run_two_clients.sh 150      avec 150 ms d'aller-retour simules
#
# Ctrl+C arrete l'ensemble.
set -euo pipefail

GODOT="${GODOT:-godot}"
LAG="${1:-0}"
PORT="${PORT:-8910}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() { kill 0 2>/dev/null || true; }
trap cleanup EXIT INT TERM

echo "Serveur dedie sur le port $PORT..."
"$GODOT" --headless --path "$PROJECT_DIR" -- --server --port "$PORT" &
sleep 2

echo "Client 1 (latence simulee : ${LAG} ms)..."
"$GODOT" --path "$PROJECT_DIR" -- --join 127.0.0.1 --port "$PORT" --name "Joueur 1" --lag "$LAG" &
sleep 1

echo "Client 2 (latence simulee : ${LAG} ms)..."
"$GODOT" --path "$PROJECT_DIR" -- --join 127.0.0.1 --port "$PORT" --name "Joueur 2" --lag "$LAG" &

wait
