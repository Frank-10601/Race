# Race — jeu de course arcade 3D multijoueur

Phase 0 : base technique. Une piste de test, une voiture pilotable, plusieurs
joueurs en reseau, et une version web jouable dans un navigateur.

> Godot 4.7 ou superieur, GDScript. Voir `CLAUDE.md` pour la vision du projet,
> les contraintes et les conventions de code.

---

## Demarrer

### Conduire seul (pour regler le ressenti)

```bash
godot --path . -- --solo
```

### Jouer a plusieurs sur une machine

```bash
tools/run_two_clients.sh        # serveur dedie + deux clients
tools/run_two_clients.sh 150    # avec 150 ms d'aller-retour simules
```

### Serveur dedie, sans affichage

```bash
tools/run_server.sh 8910 websocket
```

### Rejoindre un serveur

```bash
godot --path . -- --join 127.0.0.1 --port 8910 --name Kim
```

### Version web

```bash
tools/build_web.sh --serve      # construit puis sert sur http://localhost:8060
```

Pour heberger et partager un lien : `docs/HOSTING.md`.

---

## Commandes

| Touche | Action |
|---|---|
| Flèches ou **ZQSD** / **WASD** | accelerer, freiner, tourner |
| **Espace** | frein a main (declenche le derapage) |
| **R** | remise en piste |
| **C** | changer de camera (arriere, rapprochee, capot) |
| **F3** | panneau de debogage |
| **Echap** | quitter (sans effet dans un navigateur) |

Les touches sont lues par position physique : **ZQSD fonctionne sur un clavier
AZERTY sans rien configurer**.

---

## Options de lancement

| Option | Effet |
|---|---|
| `--solo` | conduite seule, sans reseau |
| `--host` | heberge une course et y joue |
| `--server` | serveur dedie, sans affichage |
| `--join <adresse>` | rejoint un serveur |
| `--port <n>` | port (defaut : `tuning.cfg`) |
| `--transport websocket\|enet` | transport reseau |
| `--name <pseudo>` | pseudo du joueur |
| `--max-players <n>` | joueurs maximum |
| `--lag <ms>` | latence simulee, aller-retour |
| `--jitter <ms>` | gigue simulee |
| `--autopilot` | conduite automatique (essais) |
| `--diagnostics` | rapport periodique sur la console |
| `--benchmark <s>` | mesure de performance, puis arret |

Dans un navigateur, les memes options passent par l'URL :
`index.html?join=mon-serveur.fr&port=443&name=Kim`

---

## Reglages

**Tout se regle dans `src/config/tuning.cfg`** : acceleration, vitesse maximale,
adherence, force de derapage, freinage, gravite, camera, remise en piste et taux
reseau. Le fichier est commente ligne par ligne et ne demande aucune
recompilation — il suffit de relancer.

En multijoueur, **seul le fichier du serveur compte** : il envoie ses reglages a
chaque client a la connexion, pour que la prediction du client donne exactement
le meme resultat que la simulation du serveur.

---

## Essais automatises

```bash
tools/run_tests.sh
```

Verifie la geometrie du trace et le modele de conduite : acceleration, vitesse
de pointe, freinage, sens et vivacite des virages, declenchement et stabilite du
derapage, franchissement des rampes, arret contre les murs, et surtout le
**determinisme** de la simulation, dont depend toute la prediction reseau.

Captures d'ecran automatiques (Linux sans ecran) :

```bash
xvfb-run -a godot --rendering-driver opengl3 res://tools/tests/screenshot.tscn
```

---

## Organisation

```
src/
├── config/     tous les reglages (tuning.cfg) et leur chargement
├── network/    transport, prediction, interpolation, horloge, latence simulee
├── vehicle/    simulation, visuel, remise en piste, chargement de modeles
├── track/      description et construction du circuit
├── camera/     camera de poursuite
├── ui/         menu, compteur de vitesse, panneau F3
├── main/       point d'entree, orchestration de la course, entrees joueur
└── systems/    (vide) tours, course, effets : phases 1 a 5
```

---

## Documentation

| Fichier | Contenu |
|---|---|
| `CLAUDE.md` | vision, contraintes, decisions d'architecture, conventions |
| `docs/NOTES.md` | decisions prises, limites connues, idees reportees, mesures |
| `docs/HOSTING.md` | heberger la version web, `wss`, ports, tunnels |
| `assets/vehicles/README.md` | format des modeles `.glb` attendus en phase 3 |
