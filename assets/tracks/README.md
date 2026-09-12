# Elements de decor des circuits

Vide en phase 0 : la piste de test est entierement generee par le code
(`src/track/track_builder.gd`).

A partir de la **phase 1**, depose ici les elements de decor en `.glb` :
bordures, tribunes, panneaux, arbres, batiments.

## Conventions

- 1 unite Godot = 1 metre
- origine du modele **au sol**, centree
- axe **-Z vers l'avant**
- un fichier par element, reutilisable : mieux vaut dix `.glb` places plusieurs
  fois qu'un seul enorme `.glb` de tout le circuit
