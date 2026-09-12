# Mettre le jeu en ligne — a faire une seule fois

Le jeu se construit et se publie tout seul a chaque `git push`. Il reste
**deux reglages a faire une fois** sur GitHub, que seul le proprietaire du depot
peut faire : un workflow n'a pas le droit de creer un site Pages lui-meme.

---

## 1. Rendre le depot public (si compte GitHub gratuit)

GitHub Pages sur un depot **prive** demande un abonnement **GitHub Pro**. Sur un
compte gratuit, il faut que le depot soit public.

1. https://github.com/Frank-10601/Race/settings
2. Tout en bas : **Danger Zone** > **Change visibility** > **Make public**
3. Confirmer en tapant le nom du depot

> Si tu as deja GitHub Pro, saute cette etape : Pages fonctionne sur un depot
> prive, et seules les personnes autorisees verront le jeu.

## 2. Activer Pages

1. https://github.com/Frank-10601/Race/settings/pages
2. **Source** : choisir **GitHub Actions** (et non « Deploy from a branch »)
3. Il n'y a rien a enregistrer : le choix prend effet immediatement

## 3. Lancer la publication

1. https://github.com/Frank-10601/Race/actions/workflows/deploy-web.yml
2. **Run workflow** > **Run workflow**
3. Environ deux minutes plus tard, le jeu est en ligne

**Le lien sera :** https://frank-10601.github.io/Race/

---

## Ensuite

Plus rien a faire. **Chaque `git push` reconstruit et republie le jeu**, et le
lien ne change jamais. Tu peux aussi republier a la main depuis l'onglet
**Actions** > **Publier la version web** > **Run workflow**.

---

## Essayer le jeu sans attendre

L'export web est joint a chaque execution du workflow, meme quand la publication
echoue :

1. https://github.com/Frank-10601/Race/actions
2. Ouvrir la derniere execution de **Publier la version web**
3. Section **Artifacts**, en bas : telecharger **race-web**
4. Decompresser, puis :
   ```bash
   cd race-web && python3 -m http.server 8060
   ```
5. Ouvrir http://localhost:8060

> Un export web ne s'ouvre pas en double-cliquant `index.html` : le navigateur
> refuse de charger le WebAssembly depuis le disque. Il faut un serveur HTTP,
> meme en local.

Cette archive est aussi celle a deposer sur **itch.io** si tu preferes y
heberger le jeu (voir `docs/HOSTING.md`).

---

## Ce qui marchera depuis le lien, et ce qui ne marchera pas

| | Depuis le lien GitHub Pages |
|---|---|
| **Conduire seul** | oui, immediatement |
| **Rejoindre un serveur** | oui, mais en `wss://` uniquement |
| **Heberger depuis le navigateur** | non, et le bouton y est masque |

Une page web ne peut pas ECOUTER de connexions : il n'existe pas de serveur
WebSocket dans un navigateur. Pour jouer a plusieurs, le serveur tourne sur une
machine (la tienne ou un petit serveur loue) et les joueurs s'y connectent.

Et comme GitHub Pages sert en HTTPS, le navigateur **refuse** une connexion
`ws://` non chiffree. Il faut donc `wss://`, c'est-a-dire un certificat. Le plus
simple est un tunnel Cloudflare, gratuit et sans rien ouvrir sur ta box :

```bash
tools/run_server.sh 8910 websocket &
cloudflared tunnel --url http://localhost:8910
```

Puis partage le lien avec l'adresse du tunnel :

```
https://frank-10601.github.io/Race/?join=xxxx.trycloudflare.com&port=443
```

La marche a suivre complete est dans `docs/HOSTING.md`.
