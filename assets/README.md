# Assets — depose tes fichiers ici

Ce dossier est **vide en phase 0** : le jeu n'utilise que des formes primitives
generees par le code (contrainte 4 de `CLAUDE.md`). Il est deja en place pour que
tu puisses y deposer tes fichiers au fur et a mesure, sans rien reorganiser.

## Ou mettre quoi

| Dossier | Contenu | Phase |
|---|---|---|
| `vehicles/` | modeles de voitures `.glb` | 3 |
| `tracks/` | elements de decor des circuits `.glb` | 1 |
| `textures/` | images : asphalte, herbe, ciel `.png` `.jpg` | 1 |
| `sounds/` | moteur, derapage, chocs `.ogg` `.wav` | 4 |
| `ui/` | icones et polices de l'interface | 2 |

## Deposer un fichier depuis GitHub

1. Ouvrir le dossier voulu sur GitHub
2. **Add file** > **Upload files**
3. Glisser les fichiers, puis **Commit changes**

Ou depuis ton ordinateur :

```bash
git pull
cp ~/mes-modeles/coupe.glb assets/vehicles/
git add assets/vehicles/coupe.glb
git commit -m "Ajoute le modele de la voiture coupe"
git push
```

## Formats attendus

- **Modeles** : `.glb` (glTF binaire). C'est le format que Blender exporte et que
  Godot lit directement, sans conversion.
- **Images** : `.png` pour tout ce qui a de la transparence, `.jpg` sinon.
- **Sons** : `.ogg` pour les sons longs (musique, moteur), `.wav` pour les sons
  courts (chocs).

## Regles

- **Aucune marque ni modele de voiture reel** (voir la vision dans `CLAUDE.md`).
- Noms de fichiers en **minuscules, sans espaces ni accents** : `coupe_rouge.glb`
  et non `Coupé Rouge.glb`. Godot et les serveurs web s'en portent mieux.
- 1 unite Godot = 1 metre. Verifie l'echelle avant d'exporter depuis Blender.

Les contraintes precises des modeles de vehicules (noms des noeuds, orientation,
roues separees) sont dans `vehicles/README.md`.
