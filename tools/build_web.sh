#!/usr/bin/env bash
# Construit la version web dans build/web/ — commande unique.
#
#   tools/build_web.sh              construit
#   tools/build_web.sh --serve      construit puis sert sur http://localhost:8060
#
# Variable GODOT : chemin de l'executable Godot s'il n'est pas dans le PATH.
#   GODOT=/chemin/vers/Godot_v4.7.2-stable_linux.x86_64 tools/build_web.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/build/web"
SERVE_PORT="${SERVE_PORT:-8060}"

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot introuvable. Installe-le ou indique son chemin :" >&2
	echo "  GODOT=/chemin/vers/godot tools/build_web.sh" >&2
	exit 1
fi

echo "==> Version de Godot : $("$GODOT" --version)"

# Les modeles d'export web doivent etre installes, sinon l'export echoue sans
# explication claire. Dans l'editeur : Editeur > Gerer les modeles d'exportation.
TEMPLATE_ROOT="${HOME}/.local/share/godot/export_templates"
if [ ! -d "$TEMPLATE_ROOT" ]; then
	echo "Modeles d'exportation absents ($TEMPLATE_ROOT)." >&2
	echo "Dans l'editeur : Editeur > Gerer les modeles d'exportation > Telecharger." >&2
	exit 1
fi

echo "==> Nettoyage de build/web/"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "==> Reimport des ressources"
"$GODOT" --headless --path "$PROJECT_DIR" --import >/dev/null 2>&1 || true

echo "==> Export web"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$OUTPUT_DIR/index.html"

# GitHub Pages ignore les dossiers dont le nom commence par un underscore, et
# n'applique aucun traitement Jekyll si ce fichier est present.
touch "$OUTPUT_DIR/.nojekyll"

echo
echo "==> Termine. Contenu de build/web/ :"
du -h "$OUTPUT_DIR"/* | sort -k2
echo
echo "Total : $(du -sh "$OUTPUT_DIR" | cut -f1)"
echo
echo "Pour essayer en local (le fichier ne peut pas s'ouvrir directement depuis le disque) :"
echo "  cd build/web && python3 -m http.server $SERVE_PORT"
echo "  puis ouvre http://localhost:$SERVE_PORT"

if [ "${1:-}" = "--serve" ]; then
	echo
	echo "==> Serveur local sur http://localhost:$SERVE_PORT (Ctrl+C pour arreter)"
	cd "$OUTPUT_DIR"
	exec python3 -m http.server "$SERVE_PORT"
fi
