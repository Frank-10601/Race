#!/usr/bin/env python3
"""Estampille l'export web d'un numero de version, pour vaincre le cache.

    tools/stamp_web_build.py build/web [identifiant]

Sans cela, un navigateur qui a deja ouvert le jeu continue de servir l'ancien
`index.pck` depuis son cache : la page se charge, mais avec le contenu de la
version precedente. Le symptome est deroutant — le jeu « marche », mais les
nouveautes n'apparaissent pas — et GitHub Pages ne permet pas de regler les
en-tetes HTTP qui l'eviteraient.

La parade consiste a changer l'URL des fichiers a chaque version : une URL
inconnue n'est jamais dans le cache. Deux endroits a traiter :
  - `index.js`, charge par une balise script, dont on suffixe le `src` ;
  - `index.pck` et `index.wasm`, charges par le moteur via `fetch`, qu'on
    intercepte pour leur ajouter le meme suffixe.
"""

import hashlib
import re
import subprocess
import sys
import time
from pathlib import Path

PATCH_TEMPLATE = """<script>
// Numero de version de cet export. Change a chaque construction : les fichiers
// du jeu sont alors demandes a une URL inedite, que le cache ne peut pas servir.
window.RACE_BUILD = "{build_id}";
(function () {{
	var pattern = /\\.(pck|wasm)$/;
	var original = window.fetch;
	window.fetch = function (resource, options) {{
		try {{
			var url = typeof resource === "string" ? resource : (resource && resource.url);
			if (typeof url === "string" && pattern.test(url.split("?")[0])) {{
				var stamped = url + (url.indexOf("?") >= 0 ? "&" : "?") + "v=" + window.RACE_BUILD;
				return original.call(this, stamped, options);
			}}
		}} catch (error) {{
			// En cas de doute, on laisse passer la requete telle quelle : mieux
			// vaut un cache mal rafraichi qu'un jeu qui ne se charge pas.
		}}
		return original.call(this, resource, options);
	}};
}})();
</script>
"""


def build_identifier():
	"""Identifiant de version : le commit courant, ou l'heure a defaut."""
	if len(sys.argv) > 2:
		return sys.argv[2]
	try:
		revision = subprocess.run(
			["git", "rev-parse", "--short", "HEAD"],
			capture_output=True, text=True, timeout=10, check=True)
		return revision.stdout.strip()
	except (subprocess.SubprocessError, FileNotFoundError):
		return hashlib.sha1(str(time.time()).encode()).hexdigest()[:8]


def main():
	directory = Path(sys.argv[1] if len(sys.argv) > 1 else "build/web")
	page = directory / "index.html"
	if not page.exists():
		print(f"Introuvable : {page}", file=sys.stderr)
		return 1

	build_id = build_identifier()
	html = page.read_text(encoding="utf-8")

	# 1. Le script principal, charge par une balise <script src>.
	html, replaced = re.subn(
		r'(<script[^>]*\ssrc=")(index\.js)(")',
		lambda match: f'{match.group(1)}{match.group(2)}?v={build_id}{match.group(3)}',
		html, count=1)
	if replaced == 0:
		print("Avertissement : balise script index.js introuvable.", file=sys.stderr)

	# 2. Les fichiers charges par le moteur, interceptes au niveau de `fetch`.
	patch = PATCH_TEMPLATE.format(build_id=build_id)
	if "RACE_BUILD" in html:
		print("Deja estampille.")
	elif "</head>" in html:
		html = html.replace("</head>", patch + "</head>", 1)
	else:
		html = patch + html

	page.write_text(html, encoding="utf-8")
	print(f"Export estampille : version {build_id}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
