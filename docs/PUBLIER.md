# Le jeu en ligne

**https://frank-10601.github.io/Race/**

La mise en place est faite : depot public, Pages alimente par GitHub Actions.
**Chaque `git push` reconstruit et republie le jeu**, en une minute environ, et
le lien ne change jamais. Pour republier a la main : onglet **Actions** >
**Publier la version web** > **Run workflow**.

---

## Si la publication cesse de fonctionner

Verifier dans l'ordre :

1. **Le workflow est-il passe ?**
   https://github.com/Frank-10601/Race/actions — un echec y est explique.
2. **Pages pointe-t-il toujours sur Actions ?**
   https://github.com/Frank-10601/Race/settings/pages — **Source** doit indiquer
   **GitHub Actions**, et non « Deploy from a branch ».
3. **Le depot est-il toujours public ?**
   Repasser le depot en prive coupe Pages, sauf abonnement GitHub Pro.

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
