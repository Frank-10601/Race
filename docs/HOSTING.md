# Heberger et partager la version web

Trois questions se posent, dans cet ordre : ou heberger la PAGE, ou faire
tourner le SERVEUR de jeu, et comment les relier sans que le navigateur refuse
la connexion.

---

## 1. Construire

```bash
tools/build_web.sh
```

Tout arrive dans `build/web/`. Pour essayer aussitot en local :

```bash
tools/build_web.sh --serve
# puis ouvrir http://localhost:8060
```

> Un export web ne s'ouvre pas en double-cliquant `index.html` : le navigateur
> refuse de charger le WebAssembly depuis le disque (`file://`). Il faut
> toujours passer par un serveur HTTP, meme en local.

---

## 2. Heberger la page

### itch.io — le plus simple pour partager un lien

1. Creer un compte sur https://itch.io
2. **Dashboard** > **Create new project**
3. **Kind of project** : `HTML`
4. Compresser le contenu de `build/web/` — **le contenu, pas le dossier** :
   `index.html` doit se trouver a la racine de l'archive.
   ```bash
   cd build/web && zip -r ../race-web.zip .
   ```
5. Televerser `race-web.zip`, cocher **This file will be played in the browser**
6. **Embed options** : largeur 1280, hauteur 720, cocher **Fullscreen button**
7. **Visibility** : `Public` ou `Restricted` selon ce que tu veux partager
8. **Save & view page** : le lien est de la forme
   `https://ton-pseudo.itch.io/race`

**Mettre a jour** : reconstruire, recompresser, remplacer le fichier sur la page
du projet. Le lien ne change pas.

### GitHub Pages — pratique si le code est deja sur GitHub

1. Construire, puis publier le contenu de `build/web/` sur la branche `gh-pages` :
   ```bash
   tools/build_web.sh
   git checkout --orphan gh-pages
   git rm -rf .
   cp -r build/web/* build/web/.nojekyll .
   git add -A && git commit -m "Publie la version web"
   git push -u origin gh-pages
   git checkout <ta-branche>
   ```
2. Sur GitHub : **Settings** > **Pages** > **Source** : `gh-pages`, dossier `/`
3. Le lien est de la forme `https://<compte>.github.io/<depot>/`

`tools/build_web.sh` cree deja le fichier `.nojekyll`, sans lequel GitHub Pages
ignorerait certains fichiers de l'export.

> GitHub Pages ne permet pas de definir d'en-tetes HTTP. C'est pourquoi l'export
> est configure **sans threads** (`variant/thread_support=false`) : la version
> avec threads exigerait les en-tetes `Cross-Origin-Opener-Policy` et
> `Cross-Origin-Embedder-Policy`, impossibles a fournir la.

---

## 3. Faire tourner le serveur de jeu

La page web ne contient que le CLIENT. Il faut un serveur quelque part.

```bash
tools/run_server.sh 8910 websocket
```

Trois possibilites :

| Ou | Pour qui | Ce qu'il faut |
|---|---|---|
| Ta machine, en local | toi seul, essais | rien |
| Ta machine, ouverte sur Internet | des amis | ouvrir un port sur la box |
| Un petit serveur loue (VPS) | tout le monde, en permanence | un VPS et un nom de domaine |

### Ouvrir le port sur ta box

1. Donner une adresse IP fixe a ton ordinateur sur le reseau local
   (souvent « bail DHCP statique » dans l'interface de la box).
2. Dans l'interface de la box, section **NAT / redirection de ports** :
   rediriger le port **8910 en TCP** vers l'adresse locale de ton ordinateur.
   > **TCP**, pas UDP : WebSocket passe par TCP. Si tu utilises le transport
   > ENet (bureau uniquement), c'est **UDP** qu'il faut rediriger.
3. Autoriser le port dans le pare-feu de ton systeme.
4. Relever ton adresse IP publique (https://ifconfig.me) et la communiquer.

---

## 4. Le point qui bloque tout le monde : ws ou wss

Un navigateur **refuse** une connexion WebSocket non chiffree (`ws://`) depuis
une page servie en `https://`. C'est la regle du contenu mixte, et elle ne se
contourne pas.

| Page servie depuis | Connexion possible | Certificat necessaire |
|---|---|---|
| `http://localhost` | `ws://` | non |
| `https://itch.io` ou GitHub Pages | `wss://` uniquement | **oui** |

Comme itch.io et GitHub Pages servent toujours en HTTPS, **des que tu partages
un lien, il te faut `wss://`**. Le client le detecte tout seul : il regarde le
protocole de la page et choisit `ws` ou `wss` sans rien demander au joueur.

### Solution recommandee : un tunnel Cloudflare

Gratuit, aucun port a ouvrir, certificat fourni.

```bash
# Installation : https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/
tools/run_server.sh 8910 websocket &
cloudflared tunnel --url http://localhost:8910
```

`cloudflared` affiche une adresse du type
`https://quelque-chose-aleatoire.trycloudflare.com`. Le joueur la saisit
**sans le schema** dans le champ « Adresse du serveur » :
`quelque-chose-aleatoire.trycloudflare.com`, port `443`.

Ou directement par l'URL, ce qui evite toute saisie :

```
https://ton-pseudo.itch.io/race?join=quelque-chose.trycloudflare.com&port=443
```

> L'adresse d'un tunnel gratuit change a chaque lancement. Pour une adresse
> stable, un compte Cloudflare permet de creer un tunnel nomme.

### Solution permanente : un VPS avec Caddy

Sur un petit serveur loue, avec un nom de domaine pointant dessus :

```
# /etc/caddy/Caddyfile
jeu.mondomaine.fr {
    reverse_proxy localhost:8910
}
```

Caddy obtient et renouvelle le certificat tout seul. Les joueurs saisissent
`jeu.mondomaine.fr`, port `443`.

---

## 5. Recapitulatif des essais

| Situation | Page | Serveur | Adresse a saisir |
|---|---|---|---|
| Essai en solo | `http://localhost:8060` | `tools/run_server.sh` | `127.0.0.1`, port `8910` |
| Avec un ami, rapidement | itch.io | local + `cloudflared` | l'adresse du tunnel, port `443` |
| En permanence | itch.io ou Pages | VPS + Caddy | ton domaine, port `443` |

---

## 6. Si ca ne marche pas

| Symptome | Cause la plus frequente |
|---|---|
| Page blanche, console : « SharedArrayBuffer is not defined » | export construit avec les threads : verifier `variant/thread_support=false` |
| « Mixed Content: blocked » dans la console | page en https et serveur en `ws://` : il faut `wss://` (voir section 4) |
| La connexion expire sans message | port non redirige, pare-feu, ou mauvaise adresse IP publique |
| « La course est complete » | `max_players` atteint dans `src/config/tuning.cfg` |
| Le jeu tourne mais rame | voir les mesures dans `docs/NOTES.md` |
