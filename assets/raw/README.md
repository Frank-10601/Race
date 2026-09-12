# raw — depose tes fichiers bruts ici

**C'est le sas d'entree.** Tu deposes ici ce qui sort de Meshy, de Tripo, de
Blender ou d'ailleurs, **sans rien preparer**. Je m'occupe de l'inspecter, de le
nettoyer et de le ranger dans `assets/vehicles/`, `assets/tracks/`, etc.

> Ce dossier contient un fichier `.gdignore` : Godot l'ignore completement.
> Rien de ce que tu deposes ici n'entre dans le jeu tant que je ne l'ai pas
> traite, et rien ne ralentit l'ouverture du projet.

---

## Ou deposer

| Dossier | Pour |
|---|---|
| `raw/vehicles/` | voitures |
| `raw/tracks/` | decor de circuit : bordures, tribunes, panneaux, arbres |
| `raw/misc/` | tout le reste, ou si tu ne sais pas |

## Comment deposer

Depuis GitHub, sans rien installer :

1. Ouvrir le dossier voulu
2. **Add file** > **Upload files**
3. Glisser les fichiers, puis **Commit changes**

Ou depuis ton ordinateur :

```bash
git pull
cp ~/Downloads/voiture_meshy.glb assets/raw/vehicles/
git add assets/raw/vehicles/voiture_meshy.glb
git commit -m "Depose un modele brut de voiture"
git push
```

## Ce que tu peux deposer

| Format | Traitement |
|---|---|
| `.glb` `.gltf` | directement exploitable |
| `.obj` + `.mtl` | converti |
| `.fbx` | converti |
| `.zip` | decompresse, puis traite selon son contenu |
| `.png` `.jpg` | textures, redimensionnees si besoin |

**Ne te soucie ni de l'echelle, ni de l'orientation, ni des noms.** C'est
justement ce que je corrige. Depose et dis-moi a quoi ca sert.

## Inspecter un modele soi-meme

```bash
pip install pygltflib numpy      # une seule fois
tools/inspect_assets.py          # inspecte tout assets/raw/
tools/inspect_assets.py mon_modele.glb
```

Le rapport donne les dimensions reelles, l'orientation, le nombre de triangles,
la taille des textures, et la liste de ce qu'il faut corriger — avec le facteur
d'echelle exact a appliquer, par exemple.

## Ce que je fais ensuite

1. **J'inspecte** : dimensions reelles, orientation, nombre de triangles,
   textures, structure des objets.
2. **Je te dis ce qui va et ce qui ne va pas.** Exemple frequent avec les
   modeles generes par IA : la carrosserie et les roues forment un seul bloc,
   et les roues ne peuvent alors ni tourner ni braquer. Il faut les separer, ce
   qui se fait dans Blender — je te dirai precisement quoi separer.
3. **Je corrige ce qui peut l'etre automatiquement** : echelle, orientation,
   origine, noms des objets, allegement des textures, compression.
4. **Je range** le resultat dans `assets/vehicles/` (ou ailleurs) avec la
   ressource Godot qui va avec, et je branche le modele dans le jeu.

## Un mot sur la taille des fichiers

GitHub avertit au-dela de 50 Mo par fichier et refuse a 100 Mo. Les modeles
generes par IA depassent souvent 20 Mo a cause de leurs textures : je les
allege au passage. Si tu dois deposer plus lourd, dis-le-moi, on mettra Git LFS
en place.

## Faut-il garder les fichiers bruts ?

Oui, et c'est le but de ce dossier : garder l'original permet de refaire le
traitement autrement si le resultat ne convient pas. Si le depot devient trop
lourd, on fera le menage ensemble.
